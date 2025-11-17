# Raspberry Pi Setup Guide – Edge Forestry Flutter App

MODELS ARE NOT INCLUDED AND PROPRIETARY TO EDGE FORESTRY AI

## Introduction
This guide provides a step-by-step walkthrough for setting up the **Edge Forestry Flutter Application** on a **Raspberry Pi 4**.  
It covers hardware assembly, OS installation, dependency setup, and service configuration.  
By the end, your application will **automatically launch at startup**.

---

## Prerequisites

### Hardware
- Raspberry Pi 4B (8GB RAM)
- Raspberry Pi 7-inch LED Touchscreen Kit
- Compatible Raspberry Pi tablet case
- Two MicroSD cards
- USB SD card reader
- Micro HDMI cable
- USB-C power cable
- RTC Module (DS3231)

### Tools
- Small Phillips screwdriver

### Software
- [Raspberry Pi Imager](https://www.raspberrypi.com/software)
- [Flutter SDK](https://flutter.dev)
- Git

### User Account
- Username: `edgeforestry`
- Password: `efai`

---

## 1. Flash the Operating System

1. Install **Raspberry Pi Imager**.  
2. Insert a MicroSD card into your USB SD card reader.  
3. In Imager:
   - Device: **Raspberry Pi 4**
   - OS: **Raspberry Pi OS (64-bit) with Desktop and Recommended Software**
   - Configure custom settings:
     - Username: `edgeforestry`
     - Password: `efai`
4. Flash the OS and safely eject the card.

---

## 2. Boot and Configure the Pi

1. Insert the MicroSD card into the Raspberry Pi.
2. Connect:
   - Monitor (Micro HDMI)
   - Keyboard and Mouse (USB)
   - Power cable (USB-C)
3. On first boot:
   - Complete setup wizard
   - Connect to Wi-Fi to enable repository cloning

---

## 3. Install Software and Dependencies

### Connect Git SSH
Follow [GitHub SSH Setup Docs](https://docs.github.com/en/authentication/connecting-to-github-with-ssh) for easier access.

### Clone the Repository
Enter terminal
git clone git@github.com:edgeforestry/rasp-pi-flutter-app.git

### Update System and Install Python 13.2.7
sudo apt update && sudo apt upgrade -y
sudo apt install -y make build-essential libssl-dev zlib1g-dev \
libncursesw5-dev libreadline-dev libsqlite3-dev libffi-dev \
liblzma-dev wget
cd /usr/src
sudo wget https://www.python.org/ftp/python/3.12.7/Python-3.12.7.tgz
sudo tar -xf Python-3.12.7.tgz
cd Python-3.12.7
sudo ./configure --enable-optimizations --enable-shared LDFLAGS="-Wl,-rpath /usr/local/lib"
sudo make -j$(nproc)
sudo make altinstall

### Set Python 3.12.7 as Default
echo "alias python=python3.12" >> ~/.bashrc
source ~/.bashrc
python3.12 --version

### Install GitLFS
curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | sudo bash
sudo apt install -y git-lfs
git lfs install
git lfs version

### Setup Venv
cd ~/rasp-pi-flutter-app
python3.12 -m venv venv
source venv/bin/activate
cd backend
pip install -r requirements.txt

### Install Flutter SDK
cd ~
git clone https://github.com/flutter/flutter.git -b stable
echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.bashrc
source ~/.bashrc

### Build Flutter App
cd ~/rasp-pi-flutter-app
flutter config --enable-web
sudo apt install -y chromium-browser
sudo ln -s /usr/bin/chromium-browser /usr/bin/chromium

cd frontend
flutter pub get
flutter build web

## 4. Enable Startup Script
chmod +x /home/edgeforestry/rasp-pi-flutter-app/start.sh

## 5. Register Sytsemd Service
sudo nano /etc/systemd/system/ef.service

PASTE:
[Unit]
Description=Edge Forestry Flutter App
After=lightdm.service

[Service]
ExecStart=/home/edgeforestry/rasp-pi-flutter-app/start.sh
WorkingDirectory=/home/edgeforestry/rasp-pi-flutter-app
User=edgeforestry
Environment=DISPLAY=:0
StandardOutput=journal
StandardError=journal
Restart=always
RestartSec=5
TimeoutStartSec=0

[Install]
WantedBy=graphical.target

Save (Ctrl + 0, Enter) and Exit (Ctrl + X)

### Enable and Start
sudo systemctl enable ef.service
sudo systemctl start ef.service

## 6. RTC Module COnfiguration
### Enable I2C
sudo raspi-config
#### Interface Options → I2C → Enable
sudo reboot

### Detect RTC
sudo apt install -y i2c-tools
sudo i2cdetect -y 1
You should see address 0x68

## Load at Startup
sudo nano /boot/config.txt

### Add
dtoverlay=i2c-rtc,ds3231

### Save and Reboot
sudo reboot

### Verify
dmesg | grep rtc
timedatectl

### If using hwclock:
sudo apt remove -y fake-hwclock
sudo systemctl disable fake-hwclock
sudo hwclock -w

## 7. Change App Orientation
Open Raspberry Pi Menu → Preferences → Screen Configuration

Select your display → Orientation: Left → Apply

Follow touch adjustment guide:
[DFRobot Display Setup](https://core-electronics.com.au/guides/raspberry-pi/dfrobot-8.9-ips-display/)

## 8. Assemble Hardware
Attach the Pi to the touchscreen mount with screws.

Connect:
Red wire → 5V
Black wire → GND
Insert ribbon cable connectors (contacts inward) and secure clasps.

## 9. Debugging and Maitenance
### View Logs
journalctl -u ef.service -f

### Start Service
sudo systemctl start ef.service

### Stop Service
sudo systemctl stop ef.service

### Exit Kiosk Mode
Alt + F4 (auto-restarts after 5 seconds)

## 10. Updating Changes in Flutter
sudo lsof -i :<port_number>
kill <pid>

cd ~/rasp-pi-flutter-app/frontend
flutter clean
flutter pub get
flutter build web
### Clear Cache in Browser Settings as well

## 11. Stress Testing (V1 Device Only)
cd ~/rasp-pi-flutter-app/StressTest
./startTest.sh
### Stop:
Ctrl + C
python3 fakeUsb.py cleanup

## 12. Final Verification
sudo reboot
