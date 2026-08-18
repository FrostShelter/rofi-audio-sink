# rofi-audio-sink

A lightweight PipeWire volume mixer and manager for [Rofi](https://github.com/davatorium/rofi).

## Dependencies

* `rofi`
* `wireplumber`
## Attentive

Please don't disable the rofi search bar (input bar) in the rofi config.

## Installation

Clone the repository and make the script executable:

```bash
git clone https://github.com/FrostShelter/rofi-audio-sink.git
cd rofi-audio-sink
sudo install -Dm755 rofi-audio-sink.sh /usr/local/bin/rofi-sink
cd ~
rm -rf ~/rofi-audio-sink

```
## Usage
In any terminal type:

```bash
rofi-sink
```
## Uninstall
To remove the binary from your system:

```bash
sudo rm /usr/local/bin/rofi-sink
hash -r
```

## Acknowledgements

Thanks for the inspiration!

* [rofi-bluetooth](https://github.com/nickclyde/rofi-bluetooth)
* [networkmanager-dmenu](https://github.com/firecat53/networkmanager-dmenu)
* [pavucontrol](https://github.com/pulseaudio/pavucontrol)

These projects inspired the idea of building lightweight, Rofi-based utilities for interacting with the Linux desktop.
