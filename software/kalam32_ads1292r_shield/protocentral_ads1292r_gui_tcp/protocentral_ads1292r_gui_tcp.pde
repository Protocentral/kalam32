//////////////////////////////////////////////////////////////////////////////////////////
//
//   Desktop GUI for controlling the HealthyPi HAT [ Patient Monitoring System]
//
//   Copyright (c) 2016 ProtoCentral
//   
//   This software is licensed under the MIT License(http://opensource.org/licenses/MIT). 
//   
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT 
//   NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. 
//   IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, 
//   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE 
//   SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//
//   Requires g4p_control graphing library for processing.  Built on V4.1
//   Downloaded from Processing IDE Sketch->Import Library->Add Library->G4P Install
//
/////////////////////////////////////////////////////////////////////////////////////////

import g4p_controls.*;                       // Processing GUI Library to create buttons, dropdown,etc.,
import processing.serial.*;                  // Serial Library
import grafica.*;
import processing.net.*;

// Java Swing Package For prompting message
import java.awt.*;
import javax.swing.*;
import static javax.swing.JOptionPane.*;

// File Packages to record the data into a text file
import javax.swing.JFileChooser;
import java.io.FileWriter;
import java.io.BufferedWriter;

// Date Format
import java.util.Date;
import java.text.DateFormat;
import java.text.SimpleDateFormat;

// General Java Package
import java.math.*;

Client myClient;
int dataIn;

/************** Packet Validation  **********************/
private static final int CESState_Init = 0;
private static final int CESState_SOF1_Found = 1;
private static final int CESState_SOF2_Found = 2;
private static final int CESState_PktLen_Found = 3;

/*CES CMD IF Packet Format*/
private static final int CES_CMDIF_PKT_START_1 = 0x0A;
private static final int CES_CMDIF_PKT_START_2 = 0xFA;
private static final int CES_CMDIF_PKT_STOP = 0x0B;

/*CES CMD IF Packet Indices*/
private static final int CES_CMDIF_IND_LEN = 2;
private static final int CES_CMDIF_IND_LEN_MSB = 3;
private static final int CES_CMDIF_IND_PKTTYPE = 4;
private static int CES_CMDIF_PKT_OVERHEAD = 5;

/************** Packet Related Variables **********************/

int ecs_rx_state = 0;                                        // To check the state of the packet
int CES_Pkt_Len;                                             // To store the Packet Length Deatils
int CES_Pkt_Pos_Counter, CES_Data_Counter;                   // Packet and data counter
int CES_Pkt_PktType;                                         // To store the Packet Type

char CES_Pkt_Data_Counter[] = new char[1000];                // Buffer to store the data from the packet
char ces_pkt_ecg_bytes[] = new char[4];                    // Buffer to hold ECG data
char ces_pkt_resp_bytes[] = new char[4];                   // Respiration Buffer
char ces_pkt_hr_bytes[] = new char[4];                // Buffer for SpO2 IR

int pSize = 1000;                                            // Total Size of the buffer
int arrayIndex = 0;                                          // Increment Variable for the buffer
float time = 0;                                              // X axis increment variable

// Buffer for ecg,spo2,respiration,and average of thos values
float[] xdata = new float[pSize];
float[] ecgdata = new float[pSize];
float[] bpmArray = new float[pSize];
float[] ecg_avg = new float[pSize];                          

float[] respdata = new float[pSize];

/************** Graph Related Variables **********************/

double ecg,resp, rtor_value, hr;  // To store the current ecg value
boolean startPlot = false;                             // Conditional Variable to start and stop the plot

GPlot plotECG;
GPlot plotResp;

int step = 0;
int stepsPerCycle = 100;
int lastStepTime = 0;
boolean clockwise = true;
float scale = 5;

/************** File Related Variables **********************/

boolean logging = false;                                // Variable to check whether to record the data or not
FileWriter output;                                      // In-built writer class object to write the data to file
JFileChooser jFileChooser;                              // Helps to choose particular folder to save the file
Date date;                                              // Variables to record the date related values                              
BufferedWriter bufferedWriter;
DateFormat dateFormat;

/************** Port Related Variables **********************/

Serial port = null;                                     // Oject for communicating via serial port
String[] comList;                                       // Buffer that holds the serial ports that are paired to the laptop
char inString = '\0';                                   // To receive the bytes from the packet
String selectedPort;                                    // Holds the selected port number

/************** Logo Related Variables **********************/

PImage logo;
boolean gStatus;                                        // Boolean variable to save the grid visibility status

int nPoints1 = pSize;
int totalPlotsHeight=0;
int totalPlotsWidth=0;
int toprectheight=60;

float min, max;                                      // Stores Minimum and Maximum Value
double threshold;                                    // Stores the threshold 
float minimizedVolt[] = new float[pSize];            // Stores the absoulte values in the buffer
int beats = 0, bpm = 0;                              // Variables to store the no.of peaks and bpm
int sampleRate = 125;

public void setup() 
{
  println(System.getProperty("os.name"));
  
  GPointsArray pointsECG = new GPointsArray(nPoints1);
  GPointsArray pointsResp = new GPointsArray(nPoints1);

  size(800, 480, JAVA2D);
  //fullScreen();
  /* G4P created Methods */
  createGUI();
  customGUI();
  
  totalPlotsHeight=height-toprectheight-20;

  plotECG = new GPlot(this);
  plotECG.setPos(0,toprectheight);
  plotECG.setDim(width, (totalPlotsHeight/2));
  plotECG.setBgColor(0);
  plotECG.setBoxBgColor(0);
  plotECG.setLineColor(color(0, 255, 0));
  plotECG.setLineWidth(3);
  plotECG.setMar(0,0,0,0);
  
  plotResp = new GPlot(this);
  plotResp.setPos(0,toprectheight+(totalPlotsHeight/2));
  plotResp.setDim(width, (totalPlotsHeight/2));
  plotResp.setBgColor(0);
  plotResp.setBoxBgColor(0);
  plotResp.setLineColor(color(0,0,255));
  plotResp.setLineWidth(3);
  plotResp.setMar(0,0,0,0);
  
  for (int i = 0; i < nPoints1; i++) 
  {
    pointsECG.add(i,0);
    pointsResp.add(i,0);
  }

  plotECG.setPoints(pointsECG);
  plotResp.setPoints(pointsResp);
  
  /*******  Initializing zero for buffer ****************/

  for (int i=0; i<pSize; i++) 
  {
    ecgdata[i] = 0;
  }
  time = 0;
  
  myClient = new Client(this,"192.168.1.101",4567);
  startPlot=true;
  
  label1.setFont(new Font("Monospaced", Font.PLAIN, 14));
  label1.setLocalColorScheme(GCScheme.YELLOW_SCHEME);
  label11.setFont(new Font("Arial", Font.PLAIN, 14));
}

void ClientEvent(Client someClient)
{
  inString=myClient.readChar();
    println(inString);
  pc_processData(inString);
  

}
public void draw() 
{
  background(0);
  GPointsArray pointsECG = new GPointsArray(nPoints1);
  GPointsArray pointsResp = new GPointsArray(nPoints1);

  if (startPlot)                             // If the condition is true, then the plotting is done
  {
    for(int i=0; i<nPoints1;i++)
    {    
      pointsECG.add(i,ecgdata[i]);
      pointsResp.add(i,respdata[i]);
    }
  } 

  plotECG.setPoints(pointsECG);
  plotResp.setPoints(pointsResp);
  
  plotECG.beginDraw();
  plotECG.drawBackground();
  plotECG.drawLines();
  plotECG.endDraw();
  
  plotResp.beginDraw();
  plotResp.drawBackground();
  plotResp.drawLines();
  plotResp.endDraw();
  
  pushStyle();
  noStroke();
  fill(255, 255, 255);
  rect(0, 0, width, 60);
  popStyle();
}

/*********************************************** Opening Port Function ******************************************* **************/

void startSerial()
{
  try
  {
    port = new Serial(this, selectedPort, 115200);
    port.clear();
    startPlot = true;
  }
  catch(Exception e)
  {

    showMessageDialog(null, "Port is busy", "Alert", ERROR_MESSAGE);
    System.exit (0);
  }
}

/*********************************************** Serial Port Event Function *********************************************************/

///////////////////////////////////////////////////////////////////
//
//  Event Handler To Read the packets received from the Device
//
//////////////////////////////////////////////////////////////////

void serialEvent (Serial blePort) 
{
  inString = blePort.readChar();
  pc_processData(inString);
}

/*********************************************** Getting Packet Data Function *********************************************************/

///////////////////////////////////////////////////////////////////////////
//  
//  The Logic for the below function :
//      //  The Packet recieved is separated into header, footer and the data
//      //  If Packet is not received fully, then that packet is dropped
//      //  The data separated from the packet is assigned to the buffer
//      //  If Record option is true, then the values are stored in the text file
//
//////////////////////////////////////////////////////////////////////////

void pc_processData(char rxch)
{
  switch(ecs_rx_state)
  {
  case CESState_Init:
    if (rxch==CES_CMDIF_PKT_START_1)
      ecs_rx_state=CESState_SOF1_Found;
    break;

  case CESState_SOF1_Found:
    if (rxch==CES_CMDIF_PKT_START_2)
      ecs_rx_state=CESState_SOF2_Found;
    else
      ecs_rx_state=CESState_Init;                    //Invalid Packet, reset state to init
    break;

  case CESState_SOF2_Found:
    ecs_rx_state = CESState_PktLen_Found;
    CES_Pkt_Len = (int) rxch;
    CES_Pkt_Pos_Counter = CES_CMDIF_IND_LEN;
    CES_Data_Counter = 0;
    break;

  case CESState_PktLen_Found:
    CES_Pkt_Pos_Counter++;
    if (CES_Pkt_Pos_Counter < CES_CMDIF_PKT_OVERHEAD)  //Read Header
    {
      if (CES_Pkt_Pos_Counter==CES_CMDIF_IND_LEN_MSB)
        CES_Pkt_Len = (int) ((rxch<<8)|CES_Pkt_Len);
      else if (CES_Pkt_Pos_Counter==CES_CMDIF_IND_PKTTYPE)
        CES_Pkt_PktType = (int) rxch;
    } else if ( (CES_Pkt_Pos_Counter >= CES_CMDIF_PKT_OVERHEAD) && (CES_Pkt_Pos_Counter < CES_CMDIF_PKT_OVERHEAD+CES_Pkt_Len+1) )  //Read Data
    {
      if (CES_Pkt_PktType == 2)
      {
        CES_Pkt_Data_Counter[CES_Data_Counter++] = (char) (rxch);          // Buffer that assigns the data separated from the packet
      }
    } else  //All  and data received
    {
      if (rxch==CES_CMDIF_PKT_STOP)
      { 
        ces_pkt_ecg_bytes[0] = CES_Pkt_Data_Counter[0];
        ces_pkt_ecg_bytes[1] = CES_Pkt_Data_Counter[1];
        ces_pkt_ecg_bytes[2] = CES_Pkt_Data_Counter[2];
        ces_pkt_ecg_bytes[3] = CES_Pkt_Data_Counter[3];

        ces_pkt_resp_bytes[0] = CES_Pkt_Data_Counter[4];
        ces_pkt_resp_bytes[1] = CES_Pkt_Data_Counter[5];
        ces_pkt_resp_bytes[2] = CES_Pkt_Data_Counter[6];
        ces_pkt_resp_bytes[3] = CES_Pkt_Data_Counter[7];

        int data1 = ecsParsePacket(ces_pkt_ecg_bytes, ces_pkt_ecg_bytes.length-1);
        ecg = (double) data1/(Math.pow(10, 3));
        
        int data2 = ecsParsePacket(ces_pkt_resp_bytes, ces_pkt_resp_bytes.length-1);
        resp = (double) data2; ///(Math.pow(10, 3));

        // Assigning the values for the graph buffers

        time = time+1;
        xdata[arrayIndex] = time;

        ecgdata[arrayIndex] = (float)ecg;
        respdata[arrayIndex] = (float) resp;
        bpmArray[arrayIndex] = (float)ecg;
        
        arrayIndex++;
        
        if (arrayIndex == pSize)
        {  
          arrayIndex = 0;
          time = 0; 
          if (startPlot)
          {
            bpmCalc(bpmArray);
          } else
          {
            lbl_hr.setText("0");
          }
        }       

        // If record button is clicked, then logging is done

        if (logging == true)
        {
          try {
            date = new Date();
            dateFormat = new SimpleDateFormat("HH:mm:ss");
            bufferedWriter.write(dateFormat.format(date)+","+ecg+","+rtor_value+","+hr);
            bufferedWriter.newLine();
          }
          catch(IOException e) {
            println("It broke!!!");
            e.printStackTrace();
          }
        }
        ecs_rx_state=CESState_Init;
      } else
      {
        ecs_rx_state=CESState_Init;
      }
    }
    break;

  default:
    break;
  }
}

/*********************************************** Recursion Function To Reverse The data *********************************************************/

public int ecsParsePacket(char DataRcvPacket[], int n)
{
  if (n == 0)
    return (int) DataRcvPacket[n]<<(n*8);
  else
    return (DataRcvPacket[n]<<(n*8))| ecsParsePacket(DataRcvPacket, n-1);
}

/********************************************* User-defined Method for G4P Controls  **********************************************************/

///////////////////////////////////////////////////////////////////////////////
//
//  Customization of controls is done here
//  That includes : Font Size, Visibility, Enable/Disable, ColorScheme, etc.,
//
//////////////////////////////////////////////////////////////////////////////

public void customGUI() 
{  
  comList = port.list();
  String comList1[] = new String[comList.length+1];
  comList1[0] = "SELECT THE PORT";
  for (int i = 1; i <= comList.length; i++)
  {
    comList1[i] = comList[i-1];
  }
  comList = comList1;
  portList.setItems(comList1, 0);
  //done.setVisible(false);
}

/*************** Function to Calculate Average *********************/

double averageValue(float dataArray[])
{

  float total = 0;
  for (int i=0; i<dataArray.length; i++)
  {
    total = total + dataArray[i];
  }
  return total/dataArray.length;
}

void bpmCalc(float[] recVoltage)
{
    int j = 0, n = 0, cntr = 0;

    // Making the array into absolute (positive values only)

    for (int i=0; i<pSize; i++)
    {
      recVoltage[i] = (float)Math.abs(recVoltage[i]);
    }

    j = 0;
    for (int i = 0; i < pSize; i++)
    {
      minimizedVolt[j++] = recVoltage[i];
    }
    
    // Calculating the minimum and maximum value
    
    min = min(minimizedVolt);
    max = max(minimizedVolt);

    if ((int)min == (int)max)
    {
      lbl_hr.setText("0");
    } else
    {
      threshold = min+max;                                     // Calculating the threshold value
      threshold = (threshold) * 0.600;

      if (threshold != 0)
      {
        while (n < pSize)                                      // scan through ECG samples
        {
          if (minimizedVolt[n] > threshold)                    // ECG threshold crossed
          {
            beats++;
            n = n+40;                                          // skipping the some samples to avoid repeatation
          } else
            n++;
        }
        bpm = (beats*60)/(pSize/sampleRate);

        lbl_hr.setText(bpm+"");                                  // Calculated BPM is displayed
        beats = 0;
      } else
      {
        lbl_hr.setText("0");
      }
    }
  }