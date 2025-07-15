# Why?

Reproduce my ubuntu environment setting automate

# What?

Use stow:
https://dev.to/vvidovic/set-up-your-new-machine-in-a-blink-of-an-eye-43j7

# How?
0. Install & setup git:
```bash
sudo apt install -y git
```
Config git
```bash
git config --global user.name "vodinhphuc"
git config --global user.email "phucvd2512@gmail.com"
```

Setup ssh  key
```
ssh-keygen -t ed25519 -C "phucvd2512@gmail.com"
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub
```
Go to key manage page: https://github.com/settings/keys

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
