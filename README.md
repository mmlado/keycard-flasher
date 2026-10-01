# keycard-flasher

Flashes the [Keycard](https://keycard.tech) applet onto a Keycard development card and
loads a test identity certificate, so the card is usable right away.

It leaves the machine as it found it: everything it needs goes into a `work/` folder
next to the script and is deleted when it finishes.

## Before you start

- **This erases the card.** The Keycard applet is deleted and reinstalled, and any PIN
  and keys on it are gone for good. The script asks first when the card has a PIN set.
- **Development cards only.** The script logs in with the development card key
  (`c212e073ff8b4bbfaff4de8ab655221f`). Retail cards use other keys. Every rejected
  login counts toward a limit, and past that limit the card can never be flashed
  again. The script stops at the first rejected login. Do not retry on that card.
- **The certificate is a test certificate.** Its signing key is public, so wallets show
  the card as "not genuine" until you approve it. Do not use these cards for real funds.

## Flash a card

You need a USB smart card reader. Plug it in and put the card in it.

### macOS

```sh
git clone https://github.com/mmlado/keycard-flasher
cd keycard-flasher
./flash.sh
```

### Linux

Linux needs the smart card service. Install and start it once.

Debian or Ubuntu:

```sh
sudo apt install pcscd curl git
sudo systemctl enable --now pcscd.socket
```

Fedora:

```sh
sudo dnf install pcsc-lite curl git
sudo systemctl enable --now pcscd.socket
```

Then:

```sh
git clone https://github.com/mmlado/keycard-flasher
cd keycard-flasher
./flash.sh
```

### What you should see

The run ends with these lines, and `work/` is gone again:

```
Keycard package version on the card: 4.0
Done. This card is ready.
```

You do not have to install Java. If the machine has no JDK 17 or newer, the script
downloads a private one into `work/` and deletes it afterwards.

## Flash several cards

Keep the downloads between cards and remove them at the end.

```sh
./flash.sh --keep       # run once per card, swapping the card in between
./flash.sh --cleanup    # when you are done
```

## Build the applet from source

By default the script flashes the released CAP file. With `--build` it builds the CAP
from the [status-keycard](https://github.com/keycard-tech/status-keycard) source
instead, inside a container. For that you need docker or podman, installed and running.
The script does not install them for you.

macOS, with Colima:

```sh
brew install colima docker
colima start
```

Debian or Ubuntu, with podman:

```sh
sudo apt install podman
```

Then:

```sh
./flash.sh --build              # build tag 4.0 and flash it
./flash.sh --ref master         # build another tag or branch and flash it
```

To take the container runtime off a Mac again afterwards:

```sh
colima delete
brew uninstall colima docker
```

## Try it without a card

A dry run does everything except touch a card: it downloads, checks, builds if asked,
and generates a test certificate.

```sh
./flash.sh --dry-run
./flash.sh --build --dry-run
```

## Remove everything

A normal run removes what it installed when it finishes, even when it fails. After
runs with `--keep`, or if a run was interrupted:

```sh
./flash.sh --cleanup
```

This removes:

- The `work/` folder: GlobalPlatformPro, the CAP files, the private JDK, the source
  checkout and the build cache.
- The container image used by `--build`, but only if the script pulled it. An image
  that was already on the machine is left alone.

Nothing is installed anywhere else, so a JDK, docker or podman you already had stays
untouched.

## All options

| Option | What it does |
|---|---|
| (none) | Flash Keycard 4.0 from the released CAP file, then remove what was installed. |
| `--build` | Build the CAP from source in a container. |
| `--ref <ref>` | Build from another tag or branch. Implies `--build`. |
| `--keep` | Do not remove anything afterwards. |
| `--cleanup` | Only remove what earlier runs installed. |
| `--dry-run` | Do everything except touch a card. |
| `--yes` | Do not ask before wiping a card that has a PIN set. |
| `--help` | Show the options. |

Two environment variables:

```sh
GP_READER="ACR39U" ./flash.sh   # pick a reader by part of its name, when you have several
GP_KEY=404142434445464748494a4b4c4d4e4f ./flash.sh   # use another card manager key
```

## Status

- **macOS:** tested on real cards, upgrading from Keycard 3.2 and reinstalling over 4.0.
- **`--build`:** tested on macOS with Colima. Building tag 4.0 gives a CAP whose contents
  are byte for byte the same as the released one.
- **Linux:** written but never run. The Linux parts are in `scripts/lib/linux.sh`.
  If you try it, please report what happens.

## How it is put together

| File | Job |
|---|---|
| `flash.sh` | Reads the options and calls the three steps below. |
| `scripts/install.sh` | Downloads GlobalPlatformPro, the CAP files and, if needed, a JDK into `work/`. |
| `scripts/flash-card.sh` | The card steps: delete the old applet, load the new one, create the instances, load the certificate. |
| `scripts/remove.sh` | Deletes `work/` and the container image, if one was pulled. |
| `scripts/build-cap.sh` | For `--build`: finds docker or podman and runs the build container. |
| `scripts/container-build.sh` | What runs inside that container. |
| `scripts/lib/common.sh` | Pinned versions, checksums and shared helpers. |
| `scripts/lib/macos.sh`, `scripts/lib/linux.sh` | The parts that differ between the two systems. |
| `KeycardTool.java` | Generates the test certificate and sends the few card commands GlobalPlatformPro does not cover. |

The default run pins every download to a version and checks it against a SHA-256
checksum. A `--build` run takes the source by git tag or branch and the container image
by tag, without a checksum.

## License

MIT, see [LICENSE](LICENSE).
