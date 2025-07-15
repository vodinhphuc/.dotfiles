# Why?

Reproduce my ubuntu environment setting automate

# What?
.
Use stow:
https://dev.to/vvidovic/set-up-your-new-machine-in-a-blink-of-an-eye-43j7

# How?

1. Clone after install OS, clone this repo to home directory: 

```bash
cd ~/ && git clone git@github.com:vodinhphuc/.dotfiles.git
```
2. Gain run permission for install script: 
```bash
cd ~/.dotfiles && chmod u+x scripts/install.sh
```
3. Run install script: 
```bash
cd ~/.dotfiles && bash scripts/install.sh
```
