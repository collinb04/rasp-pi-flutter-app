Raspberry Pi Setup Guide for Edge Forestry Flutter App

1. ### Introduction ###
This guide provides a step-by-step walkthrough for setting up the Edge Forestry Flutter Application on a Raspberry Pi 4. It covers hardware assembly, OS installation, dependency setup, and service configuration to ensure smooth deployment.

2. ### Prerequisites ###
--- Hardware Requirements ---
- Raspberry Pi 4B (8GB RAM)
- Raspberry Pi 7" LED Touchscreen Kit
- Compatible Raspberry Pi Tablet Case
- 2× Micro SD Cards
- USB SD Card Reader
- Micro HDMI Cable
- USB-C Power Cable
  
--- Tools ---
- Small Phillips Screwdriver
  
--- Software ---
- Raspberry Pi Imager (latest version)
- Flutter SDK
- Git
  
--- User Account ---
- Username: edgeforestry

3. ### Flash the Operating System ###
- Download the Raspberry Pi Imager for your operating system. (find on web)
- Insert a Micro SD card using your USB SD card reader.

In the Imager App:
- Device: Select Raspberry Pi 4
- OS: Choose Raspberry Pi OS (64-bit) with Desktop and Recommended Software.
- Flash the OS to the SD card and safely eject it.

4. ### Boot & Configure the Raspberry Pi ###
- Insert the Micro SD card into the slot beneath the Raspberry Pi board.

Connect the following:
- Monitor to pi via Micro HDMI
- Keyboard and Mouse to pi via USB ports
- Power supply to pi via USB-C

On first boot:
- Follow the on-screen setup
- Connect to your Wi-Fi network (required for Git cloning)

5. ### Install Software & Dependencies ###
Clone the Flutter App Repository:
- git clone https://github.com/MichiganDNR/rasp-pi-flutter-app.git

Set Up Python and Backend Environment:
- sudo apt update
- sudo apt upgrade -y
- sudo apt install python3 python3-pip -y

- cd rasp-pi-flutter-app
- python3 -m venv venv
- source venv/bin/activate

- cd backend
- pip install -r requirements.txt

Install Flutter SDK:
- cd ~
- git clone https://github.com/flutter/flutter.git -b stable
- echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.bashrc
- source ~/.bashrc

Build the Flutter Web App:
- cd ~/rasp-pi-flutter-app
- flutter config --enable-web
- sudo apt install chromium-browser -y
- sudo ln -s /usr/bin/chromium-browser /usr/bin/google-chrome
- cd frontend
- flutter pub get
- flutter build web
  
6. ### Create Start Script ###
Ensure the startup script is executable:
- chmod +x /home/edgeforestry/rasp-pi-flutter-app/start.sh

7. ### Register Systemd Service ###
Create and edit the service file:
- sudo nano /etc/systemd/system/ef.service

Paste the following:
-----------------------------

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

-----------------------------

Save and Exit the Service:
cntrl + c --> Save
Enter/Return Button to confirm file changes
cntrl + x --> Exit

Then enable the service:
- sudo systemctl enable ef.service
- sudo systemctl start ef.service

8. ### Assemble Full Hardware Device ###
First- Screw Pi to Screen Columns

Connect Screen and Rasp Pi [Ribbon Cable] :
- Ensure Device is Not Connected to Power
- Find Your Ribbon Cable (should have came witn screen kit)
- Find the Ribbon Cable on the Rasp Pi Board
- Lift the Black Clasp Gently
- Face The Ribbon Cable Connectors Towards the Inside of the Pi Device
- Ensure the Cable is Stably Within the Connecter Slot
- Gently Push the Black Clasp Back Down to Secure the Cable on the Pi
- Now Do the Same Procees on the LED Screen Board

Connect Screen and Rasp Pi [Jumper Cables] :
- Choose the Red and Black Cables that Came with the Screen Kit
- Connect the Black Cable to the Pin Labeled GRND on The Led Screen
- Connect the Red Cable to the Pin Labeled 5V on The Led Screen
- Now Using these Same Cables~ Connect the Red Cable to the Corner Pin of the Pi
- Skip one Pin on the Same Row of the Pi and Connect the Black Cable (Pi in Landscape Orientation) 

10. ### Change App Orientation ###
   
1. Navigate the home desktop page
2. Click the Raspi Logo in the top left corner
3. Click Preferences
4. Click Screen Configuration
5. Click Screens and Choose Your Respective Screen
6. Click Orientation and Choose Left
7. Click Apply to apply changes
8. Follow the instructions under "Ajusting Touch Orientation" within this article:
   https://core-electronics.com.au/guides/raspberry-pi/dfrobot-8.9-ips-display/

### Final Notes ###
Your app should now auto-start on boot.

You can view logs using:
- journalctl -u ef.service -f
  
For debugging, you can always manually stop/start the service with:
- alt + F4 (quits the app out of kiosk mode)
  // 5 second buffer before app restarts
- sudo systemctl stop ef.service
- sudo systemctl start ef.service

When updating the software, Flutter build web tends to Cache heavily,
if you notice it is deploying the previous version, follow these steps:
- sudo lsof -i :<port_number> (if nothing is displayed, the process is killed. Otherwise look for the PID)
- kill <PID>
- cd rasp-pi-flutter-app/frontend
- flutter clean
- flutter pub get
- flutter build web

