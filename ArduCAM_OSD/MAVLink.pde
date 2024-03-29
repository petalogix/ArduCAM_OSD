#define MAVLINK_COMM_NUM_BUFFERS 1
#define MAVLINK_USE_CONVENIENCE_FUNCTIONS

#include "Mavlink_compat.h"

#ifdef MAVLINK10
# include "../GCS_MAVLink/include_v1.0/mavlink_types.h"
#else
# include "../GCS_MAVLink/include/mavlink_types.h"
#endif

// true when we have received at least 1 MAVLink packet
static bool mavlink_active;
static uint8_t crlf_count = 0;

#include "../GCS_MAVLink/include/ardupilotmega/mavlink.h"

static int packet_drops = 0;
static int parse_error = 0;

void request_mavlink_rates()
{
  const int  maxStreams = 6;
  const uint8_t MAVStreams[maxStreams] = {MAV_DATA_STREAM_RAW_SENSORS,
					  MAV_DATA_STREAM_EXTENDED_STATUS,
                                          MAV_DATA_STREAM_RC_CHANNELS,
					  MAV_DATA_STREAM_POSITION,
                                          MAV_DATA_STREAM_EXTRA1, 
                                          MAV_DATA_STREAM_EXTRA2};
  const uint16_t MAVRates[maxStreams] = {0x02, 0x02, 0x05, 0x02, 0x05, 0x02};
  for (int i=0; i < maxStreams; i++) {
    	  mavlink_msg_request_data_stream_send(MAVLINK_COMM_0,
					       apm_mav_system, apm_mav_component,
					       MAVStreams[i], MAVRates[i], 1);
  }
}

void read_mavlink(){
  mavlink_message_t msg; 
  mavlink_status_t status;
  
  // this might need to move to the flight software
  static mavlink_system_t mavlink_system = {12,1,0,0};

  //grabing data 
  while(Serial.available() > 0) { 
    uint8_t c = Serial.read();
    
            /* allow CLI to be started by hitting enter 3 times, if no
           heartbeat packets have been received */
        if (mavlink_active == 0 && millis() < 20000) {
            if (c == '\n' || c == '\r') {
                crlf_count++;
            } else {
                crlf_count = 0;
            }
            if (crlf_count == 3) {
              uploadFont();
            }
        }
    
    //trying to grab msg  
    if(mavlink_parse_char(MAVLINK_COMM_0, c, &msg, &status)) {
       mavlink_active = 1;
      //handle msg
      switch(msg.msgid) {
        case MAVLINK_MSG_ID_HEARTBEAT:
          {
            mavbeat = 1;
	    apm_mav_system    = msg.sysid;
	    apm_mav_component = msg.compid;
            apm_mav_type      = mavlink_msg_heartbeat_get_type(&msg);
#ifdef MAVLINK10             
            osd_mode = mavlink_msg_heartbeat_get_custom_mode(&msg);
            osd_nav_mode = 0;
#endif            
            lastMAVBeat = millis();
            if(waitingMAVBeats == 1){
              enable_mav_request = 1;
            }
          }
          break;
        case MAVLINK_MSG_ID_SYS_STATUS:
          {
#ifndef MAVLINK10            
            osd_vbat_A = (mavlink_msg_sys_status_get_vbat(&msg) / 1000.0f);
            osd_mode = mavlink_msg_sys_status_get_mode(&msg);
            osd_nav_mode = mavlink_msg_sys_status_get_nav_mode(&msg);
#else
            osd_vbat_A = (mavlink_msg_sys_status_get_voltage_battery(&msg) / 1000.0f);
#endif            
            osd_battery_remaining_A = mavlink_msg_sys_status_get_battery_remaining(&msg);
            //osd_mode = apm_mav_component;//Debug
            //osd_nav_mode = apm_mav_system;//Debug
          }
          break;
#ifndef MAVLINK10 
        case MAVLINK_MSG_ID_GPS_RAW:
          {
            osd_lat = mavlink_msg_gps_raw_get_lat(&msg);
            osd_lon = mavlink_msg_gps_raw_get_lon(&msg);
            //osd_alt = mavlink_msg_gps_raw_get_alt(&msg);
            osd_fix_type = mavlink_msg_gps_raw_get_fix_type(&msg);
          }
          break;
#else
        case MAVLINK_MSG_ID_GPS_RAW_INT:
          {
            osd_lat = mavlink_msg_gps_raw_int_get_lat(&msg) / 10000000;
            osd_lon = mavlink_msg_gps_raw_int_get_lon(&msg) / 10000000;
            //osd_alt = mavlink_msg_gps_raw_get_alt(&msg);
            osd_fix_type = mavlink_msg_gps_raw_int_get_fix_type(&msg);
          }
          break;
#endif          
        case MAVLINK_MSG_ID_GPS_STATUS:
          {
            osd_satellites_visible = mavlink_msg_gps_status_get_satellites_visible(&msg);
          }
          break;
        case MAVLINK_MSG_ID_VFR_HUD:
          {
            osd_groundspeed = mavlink_msg_vfr_hud_get_groundspeed(&msg);
            osd_heading = mavlink_msg_vfr_hud_get_heading(&msg);// * 3.60f;//0-100% of 360
            osd_throttle = mavlink_msg_vfr_hud_get_throttle(&msg);
            if(osd_throttle > 100 && osd_throttle < 150) osd_throttle = 100;//Temporary fix for ArduPlane 2.28
            if(osd_throttle < 0 || osd_throttle > 150) osd_throttle = 0;//Temporary fix for ArduPlane 2.28
            osd_alt = mavlink_msg_vfr_hud_get_alt(&msg);
          }
          break;
        case MAVLINK_MSG_ID_ATTITUDE:
          {
            osd_pitch = ToDeg(mavlink_msg_attitude_get_pitch(&msg));
            osd_roll = ToDeg(mavlink_msg_attitude_get_roll(&msg));
            osd_yaw = ToDeg(mavlink_msg_attitude_get_yaw(&msg));
          }
          break;
        default:
          //Do nothing
          break;
      }
    }
    delayMicroseconds(138);
    //next one
  }
  // Update global packet drops counter
  packet_drops += status.packet_rx_drop_count;
  parse_error += status.parse_error;

}
