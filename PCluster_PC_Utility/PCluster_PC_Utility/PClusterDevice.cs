using HidLibrary;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Management;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;
using static System.Windows.Forms.VisualStyles.VisualStyleElement;

namespace PCluster
{
    public class PClusterDevice
    {
        public string VID { get; set; }
        public string PID { get; set; }
        public string SerialID { get; set; }
        public byte LEDValue { get; set; }
        public byte LEDBrightness { get; set; }
        public byte LEDneedleBrightness { get; set; }
        public Color LEDdialColor { get; set; }
        public Color LEDneedleColor { get; set; }
        public bool Status { get; set; }
        public List<DisplayInfo> DisplayInfos { get; set; }
        public HidDevice Device { get; set; }

        public PClDisplay disp1 = new PClDisplay();
        public PClDisplay disp2 = new PClDisplay();
        public PClDisplay disp3 = new PClDisplay();
        public PClDisplay disp4 = new PClDisplay();

        public bool bootLoaderMode = new bool();
        public bool reset = new bool();
        public void update()
        {
            if (Device == null)
            {
                Device = HidDevices.Enumerate(0x1A86, 0xFE07).FirstOrDefault(); //Changed 0xE429 for 0xFE07
            }
            else
            {
                if (!Device.IsConnected)
                {
                    Status = false;
                    Device = HidDevices.Enumerate(0x1A86, 0xFE07).FirstOrDefault();
                }
                else
                {
                    Status = true;
                    disp1.Value = DisplayInfos.FirstOrDefault(item => item.ID == disp1.DisplayedInfo).Value;
                    disp2.Value = DisplayInfos.FirstOrDefault(item => item.ID == disp2.DisplayedInfo).Value;
                    disp3.Value = DisplayInfos.FirstOrDefault(item => item.ID == disp3.DisplayedInfo).Value;
                    disp4.Value = DisplayInfos.FirstOrDefault(item => item.ID == disp4.DisplayedInfo).Value;
                    byte[] reportdata = new byte[] {  0,64,0,
                            disp1.DisplayedInfo,
                            disp1.Value,
                            disp2.DisplayedInfo,
                            disp2.Value,
                            disp3.DisplayedInfo,
                            disp3.Value,
                            disp4.DisplayedInfo,
                            disp4.Value,
                            LEDValue,
                            LEDBrightness,
                            LEDdialColor.R, LEDdialColor.G, LEDdialColor.B,
                            LEDneedleBrightness,
                            LEDneedleColor.R, LEDneedleColor.G, LEDneedleColor.B
          };
                    if (reset)
                    {
                        reset = false;
                        reportdata[2] = 41;
                    }
                    if (bootLoaderMode)
                    {
                        reportdata[2] = 42;
                    }
                    HidReport report = new HidReport(reportdata.Length, new HidDeviceData(reportdata, HidDeviceData.ReadStatus.Success));
                    report.ReportId = 0x55;
                    try
                    {
                        Console.WriteLine("reportLength: " + report.Data.Length);
                        Device.WriteReport(report);
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine("Error writing report: " + ex.Message);
                        Status = false;
                    }
                    if (bootLoaderMode)
                    {
                        bootLoaderMode = false;
                        Device.CloseDevice();
                    }


                }

            }

        }

        public PClusterDevice(HidDevice device)
        {
            DisplayInfos = new List<DisplayInfo>();
            InitializeDisplayInfos();
            Device = device;
        }

        private void InitializeDisplayInfos()
        {
            DisplayInfos.Add(new DisplayInfo(0, "OFF", 0));
            DisplayInfos.Add(new DisplayInfo(1, "CPU Usage", 0));
            DisplayInfos.Add(new DisplayInfo(2, "CPU Temp", 0));
            DisplayInfos.Add(new DisplayInfo(3, "Memory Usage", 0));
            DisplayInfos.Add(new DisplayInfo(4, "GPU Usage", 0));
            DisplayInfos.Add(new DisplayInfo(5, "GPU Temp", 0));
            DisplayInfos.Add(new DisplayInfo(6, "Disk Speed", 0));
            DisplayInfos.Add(new DisplayInfo(7, "Disk Usage", 0));
            DisplayInfos.Add(new DisplayInfo(8, "Internet Speed", 0));
            DisplayInfos.Add(new DisplayInfo(9, "CPU Power Draw", 0));
            DisplayInfos.Add(new DisplayInfo(10, "CPU Frequency", 0));
            DisplayInfos.Add(new DisplayInfo(11, "GPU Core Frequency", 0));
            DisplayInfos.Add(new DisplayInfo(12, "GPU Memory Frequency", 0));

            // Adding CPU Core usages
            for (int i = 0; i < Environment.ProcessorCount; i++)
            {
                DisplayInfos.Add(new DisplayInfo(13 + i, $"CPU Core {i + 1} Usage", 0));
            }
        }
    }

    public class DisplayInfo
    {
        public int ID { get; set; }
        public byte Value { get; set; }
        public string MenuValue { get; set; }

        public DisplayInfo(int id, string menuValue, byte value)
        {
            ID = id;
            Value = value;
            MenuValue = menuValue;
        }
    }

    public class PClDisplay
    {
        public byte Value { get; set; }
        public byte DisplayedInfo { get; set; }

    }


    public class DeviceManager
    {
        private ManagementEventWatcher watcher;
        private List<PClusterDevice> createdDevices;

        public DeviceManager()
        {
            createdDevices = new List<PClusterDevice>();

            // Create a WMI query to monitor device changes
            string query = "SELECT * FROM Win32_DeviceChangeEvent";
            watcher = new ManagementEventWatcher(query);
            watcher.EventArrived += DeviceChangeEventArrived;
        }

        public void StartMonitoring()
        {
            // Start monitoring for device changes
            watcher.Start();
        }

        public void StopMonitoring()
        {
            // Stop monitoring for device changes
            watcher.Stop();
            watcher.Dispose();
        }

        private void DeviceChangeEventArrived(object sender, EventArrivedEventArgs e)
        {
            // New device change event has arrived
            // Enumerate the new devices and process them
            IEnumerable<HidDevice> newDevices = HidDevices.Enumerate(0x1A86, 0xE429);

            foreach (HidDevice device in newDevices)
            {
                // Check if the device already has an associated PClusterDevice
                if (!createdDevices.Any(d => d.Device == device))
                {
                    PClusterDevice pClusterDevice = new PClusterDevice(device);
                    createdDevices.Add(pClusterDevice);
                    // Do something with the created PClusterDevice object
                }
            }
        }
    }
}
