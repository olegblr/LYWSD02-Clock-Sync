//  DeviceView.swift
//  LYWSD02 Clock Sync (macOS)
//
//  Created by Rick Kerkhof on 05/11/2021.
//

import CoreBluetooth
import SwiftUI
import Combine

struct DeviceView: View {
    @EnvironmentObject var bleClient: BLEClient
    
    @ObservedObject var peripheral: BLEDeviceModel
    
    @State var isPopoverPresented = false
    @State var targetDate = Date()
    
    var columns: [GridItem] = [
        GridItem(.flexible(), alignment: .trailing),
        GridItem(.flexible(), alignment: .leading),
    ]
    
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack {
            if let time = peripheral.currentTime {
                Text(time, style: .time)
                    .font(.system(size: 64)) // Doubled from .largeTitle (32 points)
                    .padding()
                    .onTapGesture {
                        isPopoverPresented = true
                    }
            }
            
            LazyVGrid(columns: columns) {
                if peripheral.hasBatterySupport {
                    // TODO: show appropriate icon for state
                    Image(systemName: "battery.100").frame(width: 30)
                    if let percent = peripheral.batteryPercentage {
                        Text(String(percent) + "%")
                            .font(.system(size: 24)) // Adjusted font size
                    } else {
                        Text("N/A")
                            .font(.system(size: 24)) // Adjusted font size
                    }
                }
                
                if peripheral.hasTemperatureSupport {
                    Image(systemName: "thermometer").frame(width: 30)
                    if let percent = peripheral.currentTemperature {
                        Text(String(percent) + " °C")
                            .font(.system(size: 24)) // Adjusted font size
                    } else {
                        Text("N/A")
                            .font(.system(size: 24)) // Adjusted font size
                    }
                }
                
                if peripheral.hasHumiditySupport {
                    Image(systemName: "drop").frame(width: 30)
                    if let percent = peripheral.currentHumidity {
                        Text(String(percent) + "%")
                            .font(.system(size: 24)) // Adjusted font size
                    } else {
                        Text("N/A")
                            .font(.system(size: 24)) // Adjusted font size
                    }
                }
            }
            
            GroupBox(label: Text("Discovered capabilities").font(.system(size: 28))) { // Adjusted font size
                VStack(alignment: .leading) {
                    HStack {
                        Image(systemName: peripheral.hasTimeSupport ? "checkmark.circle.fill" : "xmark.circle")
                        Text("Read & write time").font(.system(size: 24)) // Adjusted font size
                    }
            
                    HStack {
                        Image(systemName: peripheral.hasBatterySupport ? "checkmark.circle.fill" : "xmark.circle")
                        Text("Read battery status").font(.system(size: 24)) // Adjusted font size
                    }
                
                    HStack {
                        Image(systemName: peripheral.hasTemperatureSupport ? "checkmark.circle.fill" : "xmark.circle")
                        Text("Read temperature").font(.system(size: 24)) // Adjusted font size
                    }
                
                    HStack {
                        Image(systemName: peripheral.hasHumiditySupport ? "checkmark.circle.fill" : "xmark.circle")
                        Text("Read humidity").font(.system(size: 24)) // Adjusted font size
                    }
                }.padding()
            }.padding()
        }.toolbar {
            Button(action: {
                peripheral.sync()
            }) {
                Image(systemName: "arrow.clockwise")
                Text("Sync").font(.system(size: 24)) // Adjusted font size
            }
        }.onAppear {
            bleClient.connect(to: peripheral)
        }.onDisappear {
            bleClient.disconnect(peripheral)
        }.popover(isPresented: $isPopoverPresented) {
            VStack {
                HStack {
                    DatePicker("", selection: $targetDate)
                        .labelsHidden()
                
                    Button {
                        peripheral.syncTime(target: targetDate)
                    } label: {
                        Image(systemName: "clock.badge.checkmark")
                        Text("Set this time").font(.system(size: 24)) // Adjusted font size
                    }
                }.padding()
                Button {
                    peripheral.syncTime(target: Date())
                } label: {
                    Image(systemName: "clock.arrow.2.circlepath")
                    Text("Sync with device").font(.system(size: 24)) // Adjusted font size
                }
            }.padding()
        }
        .navigationTitle(peripheral.name) // Removed .font modifier from navigationTitle
        .onReceive(timer) { _ in
            peripheral.sync()
        }
    }
}

// struct DeviceView_Previews: PreviewProvider {
//    static var previews: some View {
//        DeviceView(peripheral: BLEDeviceModel())
//    }
// }
