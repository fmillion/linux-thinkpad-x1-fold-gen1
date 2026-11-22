# ~/.config/plasma-workspace/env/thinkpad-x1-fold-gpu.sh
# Lakefield i915 is render/media-only: render with i915, scan out via simpledrm.
for c in /sys/class/drm/card[0-9]*; do
	case "$(basename "$(readlink -f "$c/device/driver")")" in
	i915) R=/dev/dri/$(basename "$c") ;;
	simple-framebuffer) O=/dev/dri/$(basename "$c") ;;
	esac
done
if [ -n "$R" ] && [ -n "$O" ]; then
	export KWIN_DRM_DEVICES="$R:$O"
fi
export LIBVA_DRIVER_NAME=iHD
unset R O c
