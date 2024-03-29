/*

 Copyright (c) 2011.  All rights reserved.
 An Open Source Arduino based OSD and Camera Control project.
 
 Program  : ArduCAM-OSD (Supports the variant: minimOSD)
 Version  : V1.9, 14 February 2012
 Author(s): Sandro Benigno
 Coauthor(s):
   Jani Hirvinen   (All the EEPROM routines)
   Michael Oborne  (OSD Configutator)
   Mike Smith      (BetterStream and Fast Serial libraries)
 Special Contribuitor:
   Andrew Tridgell by all the support on MAVLink
   Doug Weibel by his great orientation since the start of this project
 Contributors: James Goppert, Max Levine
               and all other members of DIY Drones Dev team
 Thanks to: Chris Anderson, Jordi Munoz

 
 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with this program. If not, see <http://www.gnu.org/licenses/>
 
*/
 
/* ************************************************************ */
/* **************** MAIN PROGRAM - MODULES ******************** */
/* ************************************************************ */

#undef PROGMEM 
#define PROGMEM __attribute__(( section(".progmem.data") )) 

#undef PSTR 
#define PSTR(s) (__extension__({static prog_char __c[] PROGMEM = (s); &__c[0];})) 

//#define MAVLINK10

/* **********************************************/
/* ***************** INCLUDES *******************/

//#define membug 
//#define FORCEINIT  // You should never use this unless you know what you are doing 


// AVR Includes
#include <FastSerial.h>
#include <AP_Math.h>
#include <math.h>
#include <inttypes.h>
#include <avr/pgmspace.h>
#include "WProgram.h"
#include <EEPROM.h>
#include <SimpleTimer.h>
#include <GCS_MAVLink.h>

#ifdef membug
#include <MemoryFree.h>
#endif

// Configurations
#include "OSD_Config.h"
#include "ArduCam_Max7456.h"
#include "OSD_Vars.h"
#include "OSD_Func.h"

#include "AP_Common.h"

/* *************************************************/
/* ***************** DEFINITIONS *******************/

//OSD Hardware 
//#define ArduCAM328
#define MinimOSD

#define TELEMETRY_SPEED  57600  // How fast our MAVLink telemetry is coming to Serial port
#define BOOTTIME         2000   // Time in milliseconds that we show boot loading bar and wait user input

// Objects and Serial definitions
FastSerialPort0(Serial);

OSD osd; //OSD object 

SimpleTimer  mavlinkTimer;


/* **********************************************/
/* ***************** SETUP() *******************/

void setup() 
{
#ifdef ArduCAM328
  pinMode(10, OUTPUT); // USB ArduCam Only
#endif
  pinMode(MAX7456_SELECT,  OUTPUT); // OSD CS

  Serial.begin(TELEMETRY_SPEED);
  // setup mavlink port
  mavlink_comm_0_port = &Serial;
  
#ifdef membug
  Serial.println(freeMem());
#endif

  // Prepare OSD for displaying 
  unplugSlaves();
  osd.init();
  
  // Start 
  startPanels();
  delay(500);

// OSD debug for development (Shown at start)
#ifdef membug
     osd.setPanel(1,1);
     osd.openPanel();
     osd.printf("%i",freeMem()); 
     osd.closePanel();
#endif

// Just to easy up development things
#ifdef FORCEINIT
     InitializeOSD();
#endif


  // Check EEPROM to see if we have initialized it already or not
  // also checks if we have new version that needs EEPROM reset
  if(readEEPROM(CHK1) + readEEPROM(CHK2) != VER) {
     osd.setPanel(6,9);
     osd.openPanel();
     osd.printf_P(PSTR("Missing/Old Config")); 
     osd.closePanel();
     InitializeOSD();
  }
  
  // Get correct panel settings from EEPROM
  readSettings();
  
  // Show bootloader bar
  loadBar();

  // Startup MAVLink timers  
  mavlinkTimer.Set(&OnMavlinkTimer, 120);

  // House cleaning, clear display and enable timers
  osd.clear();
  mavlinkTimer.Enable();
    
} // END of setup();



/* ***********************************************/
/* ***************** MAIN LOOP *******************/

// Mother of all happenings, The loop()
// As simple as possible.
void loop() 
{

  if(enable_mav_request == 1){//Request rate control
    osd.clear();
    osd.setPanel(3,10);
    osd.openPanel();
    osd.printf_P(PSTR("Requesting DataStreams...")); 
    osd.closePanel();
    for(int n = 0; n < 3; n++){
      request_mavlink_rates();//Three times to certify it will be readed
      delay(50);
    }
    enable_mav_request = 0;
    delay(2000);
    osd.clear();
    waitingMAVBeats = 0;
    lastMAVBeat = millis();//Preventing error from delay sensing
  }
  
  read_mavlink();
  mavlinkTimer.Run();
}

/* *********************************************** */
/* ******** functions used in main loop() ******** */
void OnMavlinkTimer()
{
  setHeadingPatern();  // generate the heading patern

  osd_battery_pic_A = setBatteryPic(osd_battery_remaining_A);     // battery A remmaning picture
  //osd_battery_pic_B = setBatteryPic(osd_battery_remaining_B);     // battery B remmaning picture
  
  setHomeVars(osd);   // calculate and set Distance from home and Direction to home

  writePanels();       // writing enabled panels (check OSD_Panels Tab)
}


void unplugSlaves(){
  //Unplug list of SPI
#ifdef ArduCAM328
  digitalWrite(10,  HIGH); // unplug USB HOST: ArduCam Only
#endif
  digitalWrite(MAX7456_SELECT,  HIGH); // unplug OSD
}
