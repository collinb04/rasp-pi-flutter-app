Raspberry Pi Setup Guide – Edge Forestry Flutter App
1. Introduction
This guide provides a step-by-step walkthrough for setting up the Edge Forestry Flutter Application on a Raspberry Pi 4. It covers hardware assembly, operating system installation, dependency setup, and service configuration. By the end, your application will automatically launch at startup.

2. Prerequisites
Hardware: 
– Raspberry Pi 4B (8GB RAM) 
– Raspberry Pi 7-inch LED Touchscreen Kit 
– Compatible Raspberry Pi tablet case 
– Two MicroSD cards 
– USB SD card reader 
– Micro HDMI cable 
– USB-C power cable

Tools: 
– Small Phillips screwdriver

Software: 
– Raspberry Pi Imager (latest version) – available from raspberrypi.com/software 
– Flutter SDK – available from flutter.dev 
– Git

User Account: 
– Username: edgeforestry

3. Flash the Operating System
Download and install Raspberry Pi Imager. Insert a MicroSD card into the USB SD card reader. In the Imager, select Raspberry Pi 4 as the device and choose Raspberry Pi OS (64-bit) with Desktop and Recommended Software as the operating system. Flash the OS to the card and eject it safely.

4. Boot and Configure the Raspberry Pi
Insert the MicroSD card into the Pi. Connect a monitor via Micro HDMI, keyboard and mouse via USB, and the power cable via USB-C. On first boot, complete the setup wizard and connect to Wi-Fi so you can clone the repository.

5. Install Software and Dependencies
Clone the Edge Forestry Flutter App repository using:
git clone https://github.com/MichiganDNR/rasp-pi-flutter-app.git

Update and upgrade the system packages, then install Python 3 and pip:
– sudo apt update && sudo apt upgrade -y
– sudo apt install python3 python3-pip -y

Navigate into the project directory, create a Python virtual environment, activate it, then install backend requirements:
– cd rasp-pi-flutter-app
– python3 -m venv venv
– source venv/bin/activate
– cd backend
– pip install -r requirements.txt

Install the Flutter SDK by cloning the stable branch from GitHub into your home directory. Add Flutter to your PATH by appending export:  
[PATH="$PATH:$HOME/flutter/bin"] to your .bashrc file, then reload the shell with  [source ~/.bashrc.]

Build the Flutter web app by enabling web support, installing Chromium, creating a symlink so Flutter can call it as “google-chrome,” then fetching dependencies and running the Flutter build command from the frontend folder.

–  cd ~/rasp-pi-flutter-app
–  flutter config --enable-web
–  sudo apt install chromium-browser -y
–  sudo ln -s /usr/bin/chromium-browser /usr/bin/google-chrome

–  cd frontend
–  flutter pub get
–  flutter build web

6. Create Start Script
Ensure the startup script in /home/edgeforestry/rasp-pi-flutter-app/start.sh is executable by running:
– chmod +x /home/edgeforestry/rasp-pi-flutter-app/start.sh

7. Register systemd Service
Create a new service file at /etc/systemd/system/ef.service with the configuration provided in this guide. Set the description, execution command, working directory, user, environment variables, output settings, and restart policy.

Create the service:
– sudo nano /etc/systemd/system/ef.service

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
 – ctrl o to save and ctrl x to exit
 
Enable the service on boot and start it immediately using:
– sudo systemctl enable ef.service
– sudo systemctl start ef.service

8. Assemble the Hardware
First, attach the Raspberry Pi to the touchscreen mounting columns using screws.

Ribbon cable connection:
Ensure the Pi is powered off. Locate the ribbon cable connector on the Pi, lift the black clasp, insert the ribbon cable with connectors facing inward, and push the clasp down to lock it. Repeat the process on the screen’s connector.

Jumper cable connection:
Use the red and black jumper wires from the kit. On the screen, connect black to GND and red to 5V. On the Pi (in landscape orientation), connect red to the corner 5V pin and black to the GND pin one space away.

9. Change App Orientation
From the desktop, click the Raspberry Pi menu, select Preferences, then Screen Configuration. Choose your screen, set orientation to Left, and apply changes.

Follow the touch adjustment instructions here:
https://core-electronics.com.au/guides/raspberry-pi/dfrobot-8.9-ips-display/

10. Debugging and Maintenance
To view live logs:
– journalctl -u ef.service -f

To stop and start the service:
– sudo systemctl stop ef.service
– sudo systemctl start ef.service

To quit kiosk mode:
– Press Alt + F4 (the app will restart after 5 seconds).

11. Updating the App
If the Flutter web build displays an old version, first kill any process using the app’s port, then clean, fetch, and rebuild the web frontend.

– sudo lsof -i :<port_number>
– kill <PID>   # if a process is using the port

– cd rasp-pi-flutter-app/frontend
– flutter clean
– flutter pub get
– flutter build web

12. Stress Testing
Navigate to the dir using: [cd /rasp-pi-flutter-app/StressTest] and run [./startTest.sh] to begin.
– Press Ctrl + C to halt and clean up, or run:
– python3 fakeUsb.py cleanup

13. Final Verification
Reboot the Raspberry Pi using [sudo reboot]. The app should start automatically in kiosk mode.

Setup is now complete.



