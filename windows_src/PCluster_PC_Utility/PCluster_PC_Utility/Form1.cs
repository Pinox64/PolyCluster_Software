using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;
using HidLibrary;
using System.Management;
using System.IO;
using OpenHardwareMonitor.Hardware;
using System.Threading;
using PCluster;
using static System.Windows.Forms.VisualStyles.VisualStyleElement;
using System.Runtime.Remoting.Contexts;
using System.Diagnostics;
using Newtonsoft.Json;
using static PCluster_PC_Utility.Form1;
using System.Diagnostics;

namespace PCluster_PC_Utility
{

    public partial class Form1 : Form
    {
        PClusterDevice PCluster1;
        Thread hardwareUpdater;
        private ManualResetEvent pClusterInitialized = new ManualResetEvent(false);
        string[] DisplayItemsValues = { "OFF", "CPU Usage", "CPU Temp", "Memory Usage", "GPU Usage", "GPU Temp", "Disk Speed", "Disk Usage", "Internet Speed", "CPU Power Draw", "CPU Frequency", "GPU Core Frequency", "GPU Memory Frequency" };
        static float cpuTemp;
        // CPU Usage
        static float cpuUsage;
        // CPU Power Draw (Package)
        static float cpuPowerDrawPackage;
        // CPU Frequency
        static float cpuFrequency;
        // GPU Temperature
        static float gpuTemp;
        // GPU Usage
        static float gpuUsage;
        // GPU Core Frequency
        static float gpuCoreFrequency;
        // GPU Memory Frequency
        static float gpuMemoryFrequency;
        // Memory Usage (RAM)
        static float memoryUsage;
        // Disk Usage
        static float HDDUsage;
        HidDevice device;
        static Computer c = new Computer()
        {
            GPUEnabled = true,
            CPUEnabled = true,
            RAMEnabled = true
            //RAMEnabled = true, // uncomment for RAM reports
            //MainboardEnabled = true, // uncomment for Motherboard reports
            //FanControllerEnabled = true, // uncomment for FAN Reports
            //HDDEnabled = true, // uncomment for HDD Report
        };
        private bool applicationExiting = false;
        public Form1()
        {
            InitializeComponent();
        }

        private void Form1_Load(object sender, EventArgs e)
        {
            device = HidDevices.Enumerate(0x1A86, 0xE429).FirstOrDefault();
            hardwareUpdater = new Thread(ReportSystemInfo);
            hardwareUpdater.Priority = ThreadPriority.BelowNormal;
            hardwareUpdater.Start();
            //Console.WriteLine(device.Capabilities.FeatureReportByteLength);
            try
            {
                InitializeNetworkCounters(); // Initialize the network counters
            }
            catch (InvalidOperationException ex)
            {
                Console.WriteLine("Failed to initialize network counters: " + ex.Message);
            }
            pClusterInitialized.WaitOne();

            comboBox1.Items.Clear();
            comboBox2.Items.Clear();
            comboBox3.Items.Clear();
            comboBox4.Items.Clear();

            // Load JSON file
            string exeDir = AppContext.BaseDirectory;              // folder where the EXE lives
            string jsonFilePath = Path.Combine(exeDir, "config.json");
            string jsonContent = @"
                {
                    Display1 = 0,
                    Display2 = 0,
                    Display3 = 0,
                    Display4 = 0,
                    DialColor = ""#FFFFFF"",
                    NeedleColor = ""#FF0000"",
                    DialMode = 0,
                    NeedleMode = 0,
                    DialBrightness = 5,
                    NeedleBrightness = 5,
                }, Formatting.Indented);";
            try
            {
                jsonContent = File.ReadAllText(jsonFilePath);
            }
            catch
            {
                //Bad or missing config file, will create a new one
            }
            var config = JsonConvert.DeserializeObject<Config>(jsonContent);



            // Deserialize JSON to Config object


            // Access parameters
            Console.WriteLine("Display1: " + config.Display1);
            Console.WriteLine("Display2: " + config.Display2);
            Console.WriteLine("Display3: " + config.Display3);
            Console.WriteLine("Display4: " + config.Display4);

            foreach (string displayInfo in DisplayItemsValues)
            {
                comboBox1.Items.Add(displayInfo);
                comboBox1.SelectedIndex = 0;
                comboBox2.Items.Add(displayInfo);
                comboBox2.SelectedIndex = 0;
                comboBox3.Items.Add(displayInfo);
                comboBox3.SelectedIndex = 0;
                comboBox4.Items.Add(displayInfo);
                comboBox4.SelectedIndex = 0;
            }
            comboBox1.SelectedIndex = config.Display1;
            comboBox2.SelectedIndex = config.Display2;
            comboBox3.SelectedIndex = config.Display3;
            comboBox4.SelectedIndex = config.Display4;
            comboBox5.SelectedIndex = config.DialMode;
            trackBar1.Value = config.DialBrightness;
            trackBar2.Value = config.NeedleBrightness;
            // Set the button colors based on the config
            btnDialColor.BackColor = HexStringToColor(config.DialColor);
            btnNeedleColor.BackColor = HexStringToColor(config.NeedleColor);

            PCluster1.LEDBrightness = calculateBrightness(trackBar1.Value);
            PCluster1.LEDneedleBrightness = calculateBrightness(trackBar2.Value);
            PCluster1.LEDdialColor = btnDialColor.BackColor;
            PCluster1.LEDneedleColor = btnNeedleColor.BackColor;
            c.Open();
        }

        private PerformanceCounter bytesSentCounter;
        private PerformanceCounter bytesReceivedCounter;
        private float internetSpeed;

        private void InitializeNetworkCounters()
        {
            string networkInterface = GetNetworkInterface();
            bytesSentCounter = new PerformanceCounter("Network Interface", "Bytes Sent/sec", networkInterface);
            bytesReceivedCounter = new PerformanceCounter("Network Interface", "Bytes Received/sec", networkInterface);
        }

        private string GetNetworkInterface()
        {
            var category = new PerformanceCounterCategory("Network Interface");
            var instances = category.GetInstanceNames();
            if (instances.Length > 0)
            {
                foreach (var instance in instances)
                {
                    // Print all available network interfaces for debugging
                    Console.WriteLine("Found network interface: " + instance);
                    // Check for the primary network interface, you can add more checks here
                    if (!instance.ToLower().Contains("loopback") && !instance.ToLower().Contains("virtual"))
                    {
                        return instance;
                    }
                }
            }
            throw new InvalidOperationException("No suitable network interfaces found.");
        }
        public class Config //Configuration save of the values to show on each display
        {
            public int Display1 { get; set; }
            public int Display2 { get; set; }
            public int Display3 { get; set; }
            public int Display4 { get; set; }
            public string DialColor { get; set; }
            public string NeedleColor { get; set; }
            public int DialMode  { get; set; }
            public int NeedleMode { get; set; }
            public int DialBrightness { get; set; }
            public int NeedleBrightness { get; set; }
        }

        void ReportSystemInfo()
        {
            PCluster1 = new PClusterDevice(device);
            bool oldPclusterStatus = false;
            byte[] displayableValues = new byte[9];
            bytesSentCounter = new PerformanceCounter("Network Interface", "Bytes Sent/sec");
            bytesReceivedCounter = new PerformanceCounter("Network Interface", "Bytes Received/sec");
            pClusterInitialized.Set(); // Signal that PCluster1 is initialized

            while (true)
            {
                Thread.Sleep(1000);
                foreach (var hardware in c.Hardware)
                {
                    if (hardware.HardwareType == HardwareType.CPU)
                    {
                        hardware.Update();

                        foreach (var sensor in hardware.Sensors)
                        {
                            if (sensor.SensorType == SensorType.Temperature && sensor.Name.Contains("CPU Package"))
                            {
                                cpuTemp = sensor.Value.GetValueOrDefault();
                            }
                            else if (sensor.SensorType == SensorType.Load && sensor.Name.Contains("CPU Total"))
                            {
                                cpuUsage = sensor.Value.GetValueOrDefault();
                            }
                            else if (sensor.SensorType == SensorType.Load && sensor.Name.StartsWith("CPU Core #"))
                            {
                                int coreIndex = int.Parse(sensor.Name.Replace("CPU Core #", "").Trim()) - 1;
                                PCluster1.DisplayInfos.FirstOrDefault(item => item.MenuValue == $"CPU Core {coreIndex + 1} Usage").Value = (byte)sensor.Value.GetValueOrDefault();
                            }
                            else if (sensor.SensorType == SensorType.Power && sensor.Name.Contains("CPU Package"))
                            {
                                cpuPowerDrawPackage = sensor.Value.GetValueOrDefault();
                            }
                            else if (sensor.SensorType == SensorType.Clock && sensor.Name.Contains("CPU Core #1"))
                            {
                                cpuFrequency = sensor.Value.GetValueOrDefault();
                            }
                        }
                    }

                    // Targets AMD & Nvidia GPUS
                    if (hardware.HardwareType == HardwareType.GpuAti || hardware.HardwareType == HardwareType.GpuNvidia)
                    {
                        hardware.Update();

                        foreach (var sensor in hardware.Sensors)
                        {
                            if (sensor.SensorType == SensorType.Temperature && sensor.Name.Contains("GPU Core"))
                            {
                                gpuTemp = sensor.Value.GetValueOrDefault();
                            }
                            else if (sensor.SensorType == SensorType.Load && sensor.Name.Contains("GPU Core"))
                            {
                                gpuUsage = sensor.Value.GetValueOrDefault();
                            }
                            else if (sensor.SensorType == SensorType.Clock && sensor.Name.Contains("GPU Core"))
                            {
                                gpuCoreFrequency = sensor.Value.GetValueOrDefault();
                            }
                            else if (sensor.SensorType == SensorType.Clock && sensor.Name.Contains("GPU Memory"))
                            {
                                gpuMemoryFrequency = sensor.Value.GetValueOrDefault();
                            }
                        }
                    }

                    if (hardware.HardwareType == HardwareType.RAM)
                    {
                        hardware.Update();

                        foreach (var sensor in hardware.Sensors)
                        {
                            if (sensor.SensorType == SensorType.Load)
                            {
                                memoryUsage = sensor.Value.GetValueOrDefault();
                            }
                        }
                    }

                    try
                    {
                        PCluster1.DisplayInfos.FirstOrDefault(item => item.MenuValue == "CPU Usage").Value = (byte)cpuUsage;
                        PCluster1.DisplayInfos.FirstOrDefault(item => item.MenuValue == "CPU Temp").Value = (byte)cpuTemp;
                        PCluster1.DisplayInfos.FirstOrDefault(item => item.MenuValue == "GPU Usage").Value = (byte)gpuUsage;
                        PCluster1.DisplayInfos.FirstOrDefault(item => item.MenuValue == "GPU Temp").Value = (byte)gpuTemp;
                        PCluster1.DisplayInfos.FirstOrDefault(item => item.MenuValue == "Memory Usage").Value = (byte)memoryUsage;
                        PCluster1.DisplayInfos.FirstOrDefault(item => item.MenuValue == "Disk Speed").Value = (byte)HDDUsage;
                        PCluster1.DisplayInfos.FirstOrDefault(item => item.MenuValue == "CPU Power Draw").Value = (byte)cpuPowerDrawPackage;
                        PCluster1.DisplayInfos.FirstOrDefault(item => item.MenuValue == "CPU Frequency").Value = (byte)cpuFrequency;
                        PCluster1.DisplayInfos.FirstOrDefault(item => item.MenuValue == "GPU Core Frequency").Value = (byte)gpuCoreFrequency;
                        PCluster1.DisplayInfos.FirstOrDefault(item => item.MenuValue == "GPU Memory Frequency").Value = (byte)gpuMemoryFrequency;

                        // Update all CPU cores usage
                        foreach (var displayInfo in PCluster1.DisplayInfos.Where(di => di.MenuValue.StartsWith("CPU Core") && di.MenuValue.EndsWith("Usage")))
                        {
                            // The value is already updated in the loop above
                            displayInfo.Value = displayInfo.Value; // No action needed
                        }
                        // Update internet speed
                        internetSpeed = (bytesSentCounter.NextValue() + bytesReceivedCounter.NextValue()) / 1024 / 1024; // Convert to MB/s
                        PCluster1.DisplayInfos.FirstOrDefault(item => item.MenuValue == "Internet Speed").Value = (byte)internetSpeed;
                        Console.WriteLine(internetSpeed);
                        PCluster1.update();
                    }
                    catch (InvalidOperationException ex)
                    {
                        Console.WriteLine("PerformanceCounter error: " + ex.Message);
                        Thread.CurrentThread.Abort();
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine(ex);
                        Thread.CurrentThread.Abort();
                    }
                }

                if (PCluster1.Status != oldPclusterStatus)
                {
                    oldPclusterStatus = PCluster1.Status;
                    toolStripStatusLabel2.Text = PCluster1.Status ? "Connected" : "Disconnected";
                    toolStripSerialNumber.Text = PCluster1.Status ? "S/N: " + PCluster1.SerialID : "";
                }
            }
        }

        private void comboBox1_SelectedIndexChanged(object sender, EventArgs e)
        {
            if (InvokeRequired)
            {
                Invoke(new Action(() => comboBox2_SelectedIndexChanged(sender, e)));
            }
            else
            {
                try
                {
                    PCluster1.disp1.DisplayedInfo = (byte)PCluster1.DisplayInfos.FirstOrDefault(item => item.MenuValue == comboBox1.Text).ID;
                }
                catch
                {
                    Console.WriteLine("PCluster1 was null");
                }
            }
        }

        private void comboBox2_SelectedIndexChanged(object sender, EventArgs e)
        {
            if (InvokeRequired)
            {
                Invoke(new Action(() => comboBox2_SelectedIndexChanged(sender, e)));
            }
            else
            {
                try
                {
                    PCluster1.disp2.DisplayedInfo = (byte)PCluster1.DisplayInfos.FirstOrDefault(item => item.MenuValue == comboBox2.Text).ID;
                }
                catch
                {
                    Console.WriteLine("PCluster1 was null");
                }
            }
        }

        private void comboBox3_SelectedIndexChanged(object sender, EventArgs e)
        {
            if (InvokeRequired)
            {
                Invoke(new Action(() => comboBox2_SelectedIndexChanged(sender, e)));
            }
            else
            {
                try
                {
                    PCluster1.disp3.DisplayedInfo = (byte)PCluster1.DisplayInfos.FirstOrDefault(item => item.MenuValue == comboBox3.Text).ID;
                }
                catch
                {
                    Console.WriteLine("PCluster1 was null");
                }
            }
        }

        private void comboBox4_SelectedIndexChanged(object sender, EventArgs e)
        {
            if (InvokeRequired)
            {
                Invoke(new Action(() => comboBox2_SelectedIndexChanged(sender, e)));
            }
            else
            {
                try
                {
                    PCluster1.disp4.DisplayedInfo = (byte)PCluster1.DisplayInfos.FirstOrDefault(item => item.MenuValue == comboBox4.Text).ID;
                }
                catch
                {
                    Console.WriteLine("PCluster1 was null");
                }
            }
        }

        private void comboBox5_SelectedIndexChanged(object sender, EventArgs e)
        {
            PCluster1.LEDValue = (byte)comboBox5.SelectedIndex;
            Console.WriteLine("LEDValue:  " + (byte)comboBox5.SelectedIndex);
            PCluster1.LEDBrightness = calculateBrightness(trackBar1.Value);
        }

        private void trackBar1_Scroll(object sender, EventArgs e)
        {
            PCluster1.LEDBrightness = calculateBrightness(trackBar1.Value);
        }

        private void trackBar2_Scroll(object sender, EventArgs e)
        {
            PCluster1.LEDneedleBrightness = calculateBrightness(trackBar2.Value);
        }

        private byte calculateBrightness(int value)
        {// Ensure value is within the valid range
            byte[] brightnessValues = { 1, 3, 7, 12, 20, 30, 45, 60, 75, 90, 100 };

            // Ensure value is within the valid range
            if (value < 0)
            {
                value = 0;
            }
            else if (value > 10)
            {
                value = 10;
            }

            // Retrieve the corresponding brightness value from the lookup table
            byte brightness = brightnessValues[value];

            return brightness;
        }

        private void Form1_SizeChanged(object sender, EventArgs e)
        {
            if (this.WindowState == FormWindowState.Minimized)
            {
                //notifyIcon1.Icon = SystemIcons.Application;
                //notifyIcon1.BalloonTipText = "The window has been minimized to system tray";
                //notifyIcon1.ShowBalloonTip(1000);
                this.ShowInTaskbar = false;
                notifyIcon1.Visible = true;
            }


        }

        private void notifyIcon1_MouseClick(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left)
            {
                this.WindowState = FormWindowState.Normal;
                this.ShowInTaskbar = true;
            }

        }

        private void Form1_FormClosing(object sender, FormClosingEventArgs e)
        {
            if (e.CloseReason == CloseReason.UserClosing && applicationExiting == false)
            {
                e.Cancel = true;
                this.WindowState = FormWindowState.Minimized;
                //notifyIcon1.Icon = SystemIcons.Application;
                //notifyIcon1.BalloonTipText = "The window has been minimized to system tray";
                //notifyIcon1.ShowBalloonTip(1000);
                this.ShowInTaskbar = false;
                notifyIcon1.Visible = true;
            }
            else
            {
                // Allow the form to close normally
                string exeDir = AppContext.BaseDirectory;              // folder where the EXE lives
                string jsonFilePath = Path.Combine(exeDir, "config.json");
                // Deserialize JSON to Config object
                notifyIcon1.Visible = false;  // Hide the icon if the form is actually closing
                // Serialize the updated config object back to JSON
                var config = new Config
                {
                    Display1 = PCluster1.disp1.DisplayedInfo,
                    Display2 = PCluster1.disp2.DisplayedInfo,
                    Display3 = PCluster1.disp3.DisplayedInfo,
                    Display4 = PCluster1.disp4.DisplayedInfo,
                    DialColor = ColorToHexString(btnDialColor.BackColor),
                    NeedleColor = ColorToHexString(btnNeedleColor.BackColor),
                    DialMode = PCluster1.LEDValue,
                    DialBrightness = trackBar1.Value,
                    NeedleBrightness = trackBar2.Value,
                };
                string jsonContent = JsonConvert.SerializeObject(config, Formatting.Indented);

                // Write the updated JSON content back to the file
                File.WriteAllText(jsonFilePath, jsonContent);

                hardwareUpdater.Abort();
            }
        }

        // Function to get hex string for any color
        string ColorToHexString(Color color)
        {
            return $"#{color.R:X2}{color.G:X2}{color.B:X2}";
        }

        private void exitMenuItem2_Click_1(object sender, EventArgs e)
        {
            this.WindowState = FormWindowState.Normal;
            this.ShowInTaskbar = true;
        }

        private void exitMenuItem1_Click_1(object sender, EventArgs e)
        {
            // Close the application when the exit menu item is clicked
            applicationExiting = true;
            this.Close();
        }

        private void buttonBootloader_Click(object sender, EventArgs e)
        {
            PCluster1.bootLoaderMode = true;

        }

        private void buttonRst_Click(object sender, EventArgs e)
        {
            PCluster1.reset = true;
        }

        private void btnDialColor_Click(object sender, EventArgs e)
        {
            // Sets the initial color select to the current text color.
            colorDialog1.Color = btnDialColor.BackColor;

            // Update the text box color if the user clicks OK 
            if (colorDialog1.ShowDialog() == DialogResult.OK)
                btnDialColor.BackColor = colorDialog1.Color;
            PCluster1.LEDdialColor = btnDialColor.BackColor;
        }

        private void buttonExit_Click(object sender, EventArgs e)
        {
            // Close the application when the exit button is clicked
            applicationExiting = true;
            this.Close();
        }

        private void btnNeedleColor_Click(object sender, EventArgs e)
        {
            // Sets the initial color select to the current text color.
            colorDialog1.Color = btnDialColor.BackColor;

            // Update the text box color if the user clicks OK 
            if (colorDialog1.ShowDialog() == DialogResult.OK)
                btnNeedleColor.BackColor = colorDialog1.Color;
            PCluster1.LEDneedleColor = btnNeedleColor.BackColor;
        }

        // Function to convert a hex string to a Color object
        private Color HexStringToColor(string hex)
        {
            return ColorTranslator.FromHtml(hex);
        }

        private void button_test_Click(object sender, EventArgs e)
        {
            PCluster1.testMode = !PCluster1.testMode;
            if (PCluster1.testMode) button_test.BackColor = System.Drawing.Color.DarkGray;
            else button_test.BackColor = System.Drawing.Color.White;
        }
    }
}


