#!/bin/sh
# HELP: Telmi - lecteur d'histoires et de musique pour enfants
# ICON: music
# GRID: Telmi

# --- Réglages -------------------------------------------------------------
# Quand Telmi se met en veille tout seul (inactivité, fin du mode nuit) :
#   eteindre = la console s'éteint (comme sur Telmi OS)
#   quitter  = retour au menu muOS
FIN_INACTIVITE="eteindre"
# Dossier contenant Stories/, Music/ et Saves/. Vide = automatique :
#   racine d'une carte qui contient autorun.inf « TelmiOS » (carte reconnue
#   par l'appli Windows Telmi Sync), sinon le dossier de l'appli.
TELMI_ROOT=""
# ---------------------------------------------------------------------------

. /opt/muos/script/var/func.sh
APPDIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$APPDIR/telmi.log"
cd "$APPDIR" || exit 1
: >"$LOG"
echo "== Telmi $(date) ==" >>"$LOG"

export XDG_DATA_HOME="$APPDIR/save"
mkdir -p "$XDG_DATA_HOME"
ROOTS="/mnt/sdcard /mnt/mmc /mnt/usb /run/muos/storage/sdcard /run/muos/storage/mmc"
for R in $ROOTS; do
	echo "racine $R : autorun.inf=$([ -f "$R/autorun.inf" ] && echo oui || echo non) Stories=$([ -d "$R/Stories" ] && ls -1 "$R/Stories" 2>/dev/null | wc -l || echo absent)" >>"$LOG"
done
if [ -z "$TELMI_ROOT" ]; then
	# 1) carte marquée pour Telmi Sync (autorun.inf « TelmiOS »)
	for R in $ROOTS; do
		if [ -f "$R/autorun.inf" ] && grep -qi "TelmiOS" "$R/autorun.inf" 2>/dev/null; then
			TELMI_ROOT="$R"
			break
		fi
	done
fi
if [ -z "$TELMI_ROOT" ]; then
	# 2) sinon une racine qui contient un dossier Stories non vide
	for R in $ROOTS; do
		if [ -d "$R/Stories" ] && [ -n "$(ls -A "$R/Stories" 2>/dev/null)" ]; then
			TELMI_ROOT="$R"
			break
		fi
	done
fi
[ -z "$TELMI_ROOT" ] && TELMI_ROOT="$APPDIR"
mkdir -p "$TELMI_ROOT/Stories" "$TELMI_ROOT/Music" "$TELMI_ROOT/Saves/Stories"
echo "donnees Telmi : $TELMI_ROOT" >>"$LOG"
export TELMI_FULLSCREEN=1 TELMI_ROOT
TELMI_BRIGHT="$(GET_VAR "config" "settings/general/brightness" 2>/dev/null)"
TELMI_BRIGHT_MAX="$(GET_VAR "device" "screen/bright" 2>/dev/null)"
export TELMI_BRIGHT_MAX
echo "luminosite muOS=$TELMI_BRIGHT max=$TELMI_BRIGHT_MAX" >>"$LOG"
rm -f /tmp/telmi_poweroff

# --- Recherche de LÖVE 11 (même méthode que Sori Player) ---------------------
LOVE=""
addlib() { [ -d "$1" ] && export LD_LIBRARY_PATH="$1:$LD_LIBRARY_PATH"; }
use() {
	B="$1"
	shift
	[ -f "$B" ] || return 1
	if [ ! -x "$B" ]; then cp "$B" /tmp/telmi_love 2>>"$LOG" && chmod +x /tmp/telmi_love && B=/tmp/telmi_love; fi
	[ -x "$B" ] || return 1
	LOVE="$B"
	for d in "$@"; do addlib "$d"; done
	return 0
}
use "$APPDIR/bin/love" "$APPDIR/bin/lib"
if [ -z "$LOVE" ]; then
	for RT in /mnt/mmc/MUOS/PortMaster/runtimes/love_11* /mnt/sdcard/MUOS/PortMaster/runtimes/love_11* /run/muos/storage/MUOS/PortMaster/runtimes/love_11*; do
		[ -d "$RT" ] || continue
		use "$RT/love.aarch64" "$RT/libs.aarch64" "$RT/lib" "$RT" && break
	done
fi
if [ -z "$LOVE" ]; then
	SQ="$(find /mnt/mmc /mnt/sdcard /run/muos/storage -maxdepth 6 -name 'love_11*.squashfs' 2>/dev/null | head -n 1)"
	if [ -n "$SQ" ]; then
		MNT=/tmp/telmi_mnt
		mkdir -p "$MNT"
		mountpoint -q "$MNT" 2>/dev/null || mount -t squashfs -o loop "$SQ" "$MNT" >>"$LOG" 2>&1
		use "$MNT/love.aarch64" "$MNT/libs.aarch64" "$MNT/lib" || use "$MNT/love" "$MNT/libs.aarch64" "$MNT/lib"
	fi
fi
[ -z "$LOVE" ] && use /run/muos/storage/application/SoriPlayer/bin/love /run/muos/storage/application/SoriPlayer/bin/lib
[ -z "$LOVE" ] && command -v love >/dev/null 2>&1 && LOVE="$(command -v love)"
echo "LOVE : $LOVE" >>"$LOG"
[ -z "$LOVE" ] && {
	echo "LOVE 11.x aarch64 introuvable (installe le runtime love_11.5 de PortMaster, ou copie-le dans $APPDIR/bin/love)" >>"$LOG"
	exit 1
}

SETUP_APP "love" "" >>"$LOG" 2>&1
"$LOVE" "$APPDIR" >>"$LOG" 2>&1
echo "LOVE termine, code $?" >>"$LOG"
sync

# luminosité muOS d'avant Telmi
if [ -x /opt/muos/script/device/bright.sh ] && [ -n "$TELMI_BRIGHT" ] && [ "$TELMI_BRIGHT" -gt 0 ] 2>/dev/null; then
	/opt/muos/script/device/bright.sh "$TELMI_BRIGHT" >>"$LOG" 2>&1
fi

if [ -f /tmp/telmi_poweroff ]; then
	rm -f /tmp/telmi_poweroff
	if [ "$FIN_INACTIVITE" = "eteindre" ]; then
		echo "Mise en veille Telmi : extinction de la console" >>"$LOG"
		sync
		/opt/muos/script/mux/quit.sh poweroff frontend >>"$LOG" 2>&1
	fi
fi
exit 0
