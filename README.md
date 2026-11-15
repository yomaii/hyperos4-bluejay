# hyperos4-bluejay

HyperOS 4 (madrid, CN ROM) ported to the Pixel 6a (bluejay).

**Unofficial. Use at your own risk.**

Builds the system, system_ext and product images. The vendor partition, kernel and firmware stay stock Pixel.

Tested with:

- HyperOS: `OS4.0.29.0.XEOCNXM` (madrid, official CN full OTA)
- Pixel 6a: `CP2A.260705.006` (bluejay factory image)

Other versions will likely fail, because the binary and smali patches match these builds exactly.

## Working

- Calls with VoLTE, SMS, mobile data, dual SIM (physical + eSIM), Xiaomi eSIM manager
- Wi-Fi, Bluetooth, GPS, NFC
- Under-display fingerprint, including long press on the always-on display to unlock
- Face unlock (with the facehal prebuilt)
- Double tap to wake, lift to wake
- Xiaomi Camera: rear, front, 0.6x ultra wide
- 60/90Hz with the settings page (needs the kernel modules)
- Color scheme, color temperature, reading mode, paper mode
- Screen attention (Android System Intelligence)
- Power saving / performance modes (CPU limits through the Pixel power HAL)
- Glove mode (screen protector) for touch
- Charge protection and battery health
- Voice wake-up for Xiao Ai (always-on software listening)
- Liquid glass materials and launcher icon animations

## Build

Run as root on Debian or Ubuntu, with the source on a Linux filesystem.

```sh
./setup.sh
./unpack.sh --hyperos <madrid ota_full zip> --pixel <bluejay factory zip>
./build.sh
```

Images are written to `out/images/`. Run `./build.sh --help` to see the options.

Optional inputs (skipped when missing):

- `config/facehal/prebuilt/` for face unlock. Build it with `config/facehal/build_facehal.sh`.
- `config/esim/EsimLPA.apk` for the Xiaomi eSIM manager. Take it from a HyperOS 3 ROM.

## Kernel modules

```sh
git submodule update --init
./kernel/build.sh
```

This builds GKI external modules for the stock kernel into `out/kernel/`. It takes the kernel config from the Pixel `boot.img` and the symbol CRCs from the stock modules in `vendor_boot.img`, both from `work/pixel/images/`. It downloads the kernel sources and clang to `work/kernel/` (about 4 GB).

- `panel-samsung-s6e3fc3_6a.ko`: 60/90Hz panel driver (`kernel/bluejay-90hz-gamma/panel-90hz.patch`).
- `port_gamma.ko`: regamma correction at 90Hz.
- `port_thermal.ko`: Xiaomi `thermal_message` nodes (optional).

Without the 90Hz panel driver, run `build.sh` with `--no-90hz`.

## vendor_boot

```sh
tools/vendor_boot.py work/pixel/images/vendor_boot.img out/vendor_boot.img out/kernel/*.ko
```

This adds erofs entries to the first-stage fstab (the stock one only mounts ext4), replaces the panel driver and adds the other modules to the vendor ramdisk. Leave out `port_thermal.ko` if you don't want it.

Flash with vbmeta verification disabled.

## Credits

[facehal-rs](https://github.com/LazyBonesLZY/facehal-rs), SmallAICreator (crDroid Pixel 6a 90Hz mod), Lunarixus.

## License

MIT, except `kernel/` (GPL-2.0).
