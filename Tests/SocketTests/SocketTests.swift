//
//  SocketTests.swift
//  BlueSocket
//
//  Created by Bill Abt on 3/15/16.
//  Copyright © 2016 IBM. All rights reserved.
//
// 	Licensed under the Apache License, Version 2.0 (the "License");
// 	you may not use this file except in compliance with the License.
// 	You may obtain a copy of the License at
//
// 	http://www.apache.org/licenses/LICENSE-2.0
//
// 	Unless required by applicable law or agreed to in writing, software
// 	distributed under the License is distributed on an "AS IS" BASIS,
// 	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// 	See the License for the specific language governing permissions and
// 	limitations under the License.
//

// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_direct_standard_out_logs

import Dispatch
import Foundation
import Testing

#if os(Linux)
import Glibc
#endif

@testable import Socket

// .serialized because we have multiple tests using the same port.
@Suite(.serialized)
struct SocketTests {

  let QUIT: String = "QUIT"
  let port: Int32 = 1337
  let host: String = "127.0.0.1"
  let path: String = "/tmp/server.test.socket"

  func sleep(_ duration: UInt32) {
    #if os(Linux)
    _ = Glibc.sleep(duration)
    #else
    _ = Darwin.sleep(duration)
    #endif
  }

  func createHelper(family: Socket.ProtocolFamily = .inet) throws -> Socket {

    let socket = try Socket.create(family: family)
    #expect(!socket.isConnected)
    #expect(socket.isBlocking)

    return socket
  }

  func createUDPHelper(family: Socket.ProtocolFamily = .inet) throws -> Socket {

    let socket = try Socket.create(family: family, type: .datagram, proto: .udp)
    #expect(!socket.isConnected)
    #expect(socket.isBlocking)

    return socket
  }

  func launchServerHelper(family: Socket.ProtocolFamily = .inet) {

    let queue = DispatchQueue.global(qos: .userInteractive)
    queue.async {
      do {

        try self.serverHelper(family: family)

      } catch let error {

        guard let socketError = error as? Socket.Error else {

          Issue.record("Unexpected error...")
          return
        }

        Issue.record("launchServerHelper Error reported:\n \(socketError.description)")
      }
    }
  }

  func serverHelper(family: Socket.ProtocolFamily = .inet) throws {

    var keepRunning: Bool = true
    var listenSocket: Socket?

    do {

      try listenSocket = Socket.create(family: family)

      guard let listener = listenSocket else {

        Issue.record("Unable to unwrap socket...")
        return
      }

      var socket: Socket

      // Are we setting uo a TCP or UNIX based server?
      if family == .inet || family == .inet6 {

        // Setting up TCP...
        try listener.listen(on: Int(self.port), maxBacklogSize: 10)

        print("Listening on port: \(self.port)")

        socket = try listener.acceptClientConnection()

        print(
          "Accepted connection from: \(socket.remoteHostname) on port \(socket.remotePort), Secure? \(socket.signature!.isSecure)"
        )

      } else {

        // Setting up UNIX...
        try listener.listen(on: self.path, maxBacklogSize: 10)

        print("Listening on path: \(self.path)")

        socket = try listener.acceptClientConnection()

        print(
          "Accepted connection from: \(socket.remotePath!), Secure? \(socket.signature!.isSecure)"
        )

      }

      try socket.write(from: "Hello, type 'QUIT' to end session\n")

      var bytesRead = 0
      repeat {

        var readData = Data()
        bytesRead = try socket.read(into: &readData)

        if bytesRead > 0 {

          guard let response = NSString(data: readData, encoding: String.Encoding.utf8.rawValue) else {

            readData.count = 0
            Issue.record("Error decoding response...")
            break
          }

          if response.hasPrefix(self.QUIT) {

            keepRunning = false
          }

          // TCP or UNIX?
          if family == .inet || family == .inet6 {
            print(
              "Server received from connection at \(socket.remoteHostname):\(socket.remotePort): \(response) "
            )
          } else {
            print("Server received from connection at \(socket.remotePath!): \(response) ")
          }

          let reply = "Server response: \n\(response)\n"
          try socket.write(from: reply)

        }

        if bytesRead == 0 {

          break
        }

      } while keepRunning

      socket.close()
      #expect(!socket.isActive)

    } catch let error {

      guard let socketError = error as? Socket.Error else {

        Issue.record("Unexpected error...")
        return
      }

      // This error is expected when we're shutting it down...
      if socketError.errorCode == Int32(Socket.SOCKET_ERR_WRITE_FAILED) {
        return
      }
      Issue.record("serverHelper Error reported: \(socketError.description)")
    }
  }

  func launchUDPHelper(family: Socket.ProtocolFamily = .inet) {

    let queue = DispatchQueue.global(qos: .userInteractive)
    queue.async {
      do {

        try self.udpHelper(family: family)

      } catch let error {

        guard let socketError = error as? Socket.Error else {

          Issue.record("Unexpected error...")
          return
        }

        Issue.record("launchUDPHelper Error reported:\n \(socketError.description)")
      }
    }
  }

  func udpHelper(family: Socket.ProtocolFamily) throws {

    var keepRunning = true
    do {
      let socket = try createUDPHelper()
      try socket.listen(on: Int(self.port))

      repeat {

        var data = Data()

        let (bytesRead, address) = try socket.readDatagram(into: &data)

        guard let response = NSString(data: data, encoding: String.Encoding.utf8.rawValue) else {

          data.count = 0
          Issue.record("Error decoding response...")
          return
        }

        if response.hasPrefix(self.QUIT) {
          keepRunning = false
        }

        let (remoteHost, remotePort) = Socket.hostnameAndPort(from: address!)!
        print("Received \(bytesRead) bytes from \(remoteHost):\(remotePort): \(response)\n")
        print("Sending response")
        let responseString: String = "Server response: \n\(response)\n"
        try socket.write(from: responseString.data(using: String.Encoding.utf8)!, to: address!)

      } while keepRunning

    } catch let error {

      guard let socketError = error as? Socket.Error else {

        Issue.record("Unexpected error...")
        return
      }

      // This error is expected when we're shutting it down...
      if socketError.errorCode == Int32(Socket.SOCKET_ERR_WRITE_FAILED) {
        return
      }
      Issue.record("udpHelper Error reported: \(socketError.description)")
    }
  }

  func readAndPrint(socket: Socket, data: inout Data) throws -> String? {

    data.count = 0
    let	bytesRead = try socket.read(into: &data)
    if bytesRead > 0 {

      print("Read \(bytesRead) from socket...")

      guard let response = NSString(data: data as Data, encoding: String.Encoding.utf8.rawValue) else {

        Issue.record("Error accessing received data...")
        return nil
      }

      print("Response:\n\(response)")
      return String(describing: response)
    }

    return nil
  }

  @Test func testDefaultCreate() throws {

    // Create the socket...
    let socket = try createHelper()

    // Get the Signature...
    let sig = socket.signature
    #expect(sig != nil)

    // Check to ensure the family, type and protocol are correct...
    #expect(sig!.protocolFamily == Socket.ProtocolFamily.inet)
    #expect(sig!.socketType == Socket.SocketType.stream)
    #expect(sig!.proto == Socket.SocketProtocol.tcp)

    socket.close()
    #expect(!socket.isActive)
  }

  @Test func testCreateIPV6() throws {

    // Create the socket...
    let socket = try createHelper(family: .inet6)

    // Get the Signature...
    let sig = socket.signature
    #expect(sig != nil)

    // Check to ensure the family, type and protocol are correct...
    #expect(sig!.protocolFamily == Socket.ProtocolFamily.inet6)
    #expect(sig!.socketType == Socket.SocketType.stream)
    #expect(sig!.proto == Socket.SocketProtocol.tcp)

    socket.close()
    #expect(!socket.isActive)
  }

  @Test func testCreateUnix() throws {

    // Create the socket...
    let socket = try createHelper(family: .unix)

    // Get the Signature...
    let sig = socket.signature
    #expect(sig != nil)

    // Check to ensure the family, type and protocol are correct...
    #expect(sig!.protocolFamily == Socket.ProtocolFamily.unix)
    #expect(sig!.socketType == Socket.SocketType.stream)
    #expect(sig!.proto == Socket.SocketProtocol.unix)

    socket.close()
    #expect(!socket.isActive)
  }

  @Test func testCreateUDP() throws {

    // Create the socket...
    let socket = try createUDPHelper()

    // Get the Signature...
    let sig = socket.signature
    #expect(sig != nil)

    // Check to ensure the family, type and protocol are correct...
    #expect(sig!.protocolFamily == Socket.ProtocolFamily.inet)
    #expect(sig!.socketType == Socket.SocketType.datagram)
    #expect(sig!.proto == Socket.SocketProtocol.udp)

    socket.close()
    #expect(!socket.isActive)
  }

  @Test func testListen() throws {

    // Create the socket..
    let socket = try createHelper()

    // Listen on the port...
    try socket.listen(on: Int(self.port), maxBacklogSize: 10)
    #expect(socket.isListening)
    #expect(socket.listeningPort == self.port)

    // Close the socket...
    socket.close()
    #expect(!socket.isActive)
  }

  @Test func testListenPort0() throws {

    // Create the socket..
    let socket = try createHelper()

    // Listen on the port...
    try socket.listen(on: Int(0), maxBacklogSize: 10)
    #expect(socket.isListening)
    #expect(socket.listeningPort > 0)
    print("Listening port: \(socket.listeningPort)")

    // Close the socket...
    socket.close()
    #expect(!socket.isActive)
  }

  @Test func testListenUnix() throws {

    // Create the socket..
    let socket = try createHelper(family: .unix)

    // Listen on the port...
    try socket.listen(on: self.path, maxBacklogSize: 10)
    #expect(socket.isListening)
    #expect(socket.remotePath == self.path)

    // Close the socket...
    socket.close()
    #expect(!socket.isActive)
  }

  @Test func testListenUDP() throws {

    let queue = DispatchQueue.global(qos: .userInteractive)
    // Create the socket..
    let socket = try createUDPHelper()

    queue.async {

      do {
        // Listen on the port...
        var data = Data()
        _ = try socket.listen(forMessage: &data, on: Int(self.port))

      } catch let error {

        // See if it's a socket error or something else...
        guard let socketError = error as? Socket.Error else {

          Issue.record("Unexpected error...")
          return
        }

        if socketError.errorCode != Int32(Socket.SOCKET_ERR_RECV_FAILED) {
          Issue.record("testListenUDP Error reported: \(socketError.description)")
        }
      }
    }

    // Give the thread time to start...
    self.sleep(1)

    #expect(socket.isListening)
    #expect(socket.listeningPort == self.port)

    // Close the socket...
    socket.close()
    #expect(!socket.isActive)
  }

  @Test func testListenPort0UDP() throws {

    let queue = DispatchQueue.global(qos: .userInteractive)

    // Create the socket..
    let socket = try createUDPHelper()

    queue.async { [unowned socket] in

      do {
        // Listen on the port...
        var data = Data()
        _ = try socket.listen(forMessage: &data, on: Int(0))

      } catch let error {

        // See if it's a socket error or something else...
        guard let socketError = error as? Socket.Error else {

          Issue.record("Unexpected error...")
          return
        }

        if socketError.errorCode != Int32(Socket.SOCKET_ERR_RECV_FAILED) {
          Issue.record("testListenPort0UDP Error reported: \(socketError.description)")
        }
      }
    }

    // Give the thread time to start...
    self.sleep(1)

    #expect(socket.isListening)
    #expect(socket.listeningPort > 0)
    print("Listening port: \(socket.listeningPort)")

    // Close the socket...
    socket.close()
    #expect(!socket.isActive)
  }

  @Test func testConnect() throws {

    // Create the socket..
    let socket = try createHelper()

    // Listen on the port...
    try socket.listen(on: Int(self.port), maxBacklogSize: 10)
    #expect(socket.isListening)
    #expect(socket.listeningPort == self.port)

    // Create a signature...
    let signature = try Socket.Signature(
      protocolFamily: .inet,
      socketType: .stream,
      proto: .tcp,
      hostname: self.host,
      port: self.port
    )
    #expect(signature != nil)

    // Create a connected socket using the signature...
    let socket2 = try Socket.create(connectedUsing: signature!)
    #expect(socket2.isConnected)

    // Close the socket...
    socket.close()
    #expect(!socket.isActive)
    socket2.close()
    #expect(!socket2.isActive)
  }

  @Test func testConnectTo() throws {

    // Create the socket..
    let socket = try createHelper()

    // Listen on the port...
    try socket.listen(on: Int(self.port), maxBacklogSize: 10)
    #expect(socket.isListening)
    #expect(socket.listeningPort == self.port)

    // Create a second socket...
    let socket2 = try createHelper()

    // Now attempt to connect to the listening socket...
    try socket2.connect(to: self.host, port: self.port)
    #expect(socket2.isConnected)

    // Close the socket...
    socket.close()
    #expect(!socket.isActive)
    socket2.close()
    #expect(!socket2.isActive)
  }

  @Test func testConnectToWithTimeout() throws {

    // Create the socket..
    let socket = try createHelper()

    // Listen on the port...
    try socket.listen(on: Int(self.port), maxBacklogSize: 10)
    #expect(socket.isListening)
    #expect(socket.listeningPort == self.port)

    // Create a second socket...
    let socket2 = try createHelper()

    // Now attempt to connect to the listening socket...
    try socket2.connect(to: self.host, port: self.port, timeout: 1)
    #expect(socket2.isConnected)

    // Close the socket...
    socket.close()
    #expect(!socket.isActive)
    socket2.close()
    #expect(!socket2.isActive)
  }

  @Test func testConnectToPath() throws {

    // Create the socket..
    let socket = try createHelper(family: .unix)

    // Listen on the port...
    try socket.listen(on: self.path, maxBacklogSize: 10)
    #expect(socket.isListening)

    // Create a second socket...
    let socket2 = try createHelper(family: .unix)

    // Now attempt to connect to the listening socket...
    try socket2.connect(to: self.path)
    #expect(socket2.isConnected)

    // Close the socket...
    socket.close()
    #expect(!socket.isActive)
    socket2.close()
    #expect(!socket2.isActive)
  }

  @Test func testConnectPort0() throws {

    // Create the socket..
    let socket = try createHelper()

    // Listen on the port...
    try socket.listen(on: Int(0), maxBacklogSize: 10)
    #expect(socket.isListening)
    #expect(socket.listeningPort > 0)
    print("Listener signature: \(socket.signature?.description as String?)")

    // Create a signature...
    let signature = try Socket.Signature(
      protocolFamily: .inet,
      socketType: .stream,
      proto: .tcp,
      hostname: socket.remoteHostname,
      port: socket.remotePort
    )
    #expect(signature != nil)

    // Create a connected socket using the signature...
    let socket2 = try Socket.create(connectedUsing: signature!)
    #expect(socket2.isConnected)
    print("Connect signature: \(socket2.signature?.description as String?)")

    // Close the socket...
    socket.close()
    #expect(!socket.isActive)
    socket2.close()
    #expect(!socket2.isActive)
  }

  @Test func testHostnameAndPort() throws {

    // Create the socket..
    let socket = try createHelper()

    // Listen on the port...
    try socket.listen(on: Int(self.port), maxBacklogSize: 10)
    #expect(socket.isListening)
    #expect(socket.listeningPort == self.port)

    // Create a signature...
    let signature = try Socket.Signature(
      protocolFamily: .inet,
      socketType: .stream,
      proto: .tcp,
      hostname: self.host,
      port: self.port
    )
    #expect(signature != nil)

    // Create a connected socket using the signature...
    let socket2 = try Socket.create(connectedUsing: signature!)
    #expect(socket2.isConnected)

    let address = socket2.signature?.address
    #expect(address != nil)

    let (theHost, thePort) = Socket.hostnameAndPort(from: address!)!
    #expect(self.host == theHost)
    #expect(self.port == thePort)

    // Close the socket...
    socket.close()
    #expect(!socket.isActive)
    socket2.close()
    #expect(!socket2.isActive)
  }

  @Test func testBlocking() throws {

    // Create the socket...
    let socket = try createHelper()

    // Should be blocking...
    #expect(socket.isBlocking)

    // Set to non-blocking...
    try socket.setBlocking(mode: false)
    #expect(!socket.isBlocking)

    // Now back to blocking...
    try socket.setBlocking(mode: true)
    #expect(socket.isBlocking)

    // Close the socket...
    socket.close()
    #expect(!socket.isActive)
  }

  @Test func testSetReadTimeout() throws {

    // Create the socket...
    let socket = try createUDPHelper()

    // Set a timeout of 300 ms...
    try socket.setReadTimeout(value: UInt(300))

    // Try a read with nobody listening...
    var data: Data = Data()
    let (bytes, addr) = try socket.readDatagram(into: &data)
    #expect(bytes == 0)
    #expect(addr == nil)
    #expect(errno == EAGAIN)

    // Close the socket...
    socket.close()
    #expect(!socket.isActive)
  }

  @Test func testSetWriteTimeoutInet() throws {

    // Create the socket...
    let socket = try createUDPHelper(family: .inet)

    // Set a timeout of 300 ms...
    try socket.setWriteTimeout(value: UInt(300))

    // Try a write to a `bogus` address...
    let addr = Socket.createAddress(for: "foobar.org", on: 2142, family: .inet)
    #expect(addr != nil)

    // It should be noted that this write should succeed...
    //	If this was a TCP socket, the results would be different...
    let bytesWritten = try socket.write(from: Data("Hello from UDP".utf8), to: addr!)
    #expect(bytesWritten == 14)

    // Close the socket...
    socket.close()
    #expect(!socket.isActive)
  }

  @Test func testSetWriteTimeoutInet6() throws {

    // Create the socket...
    let socket = try createUDPHelper(family: .inet6)

    // Set a timeout of 300 ms...
    try socket.setWriteTimeout(value: UInt(300))

    // Try a write to a `bogus` address...
    let addr = Socket.createAddress(for: "foobar.org", on: 2142, family: .inet6)
    #expect(addr != nil)

    // It should be noted that this write should succeed...
    //	If this was a TCP socket, the results would be different...
    let bytesWritten = try socket.write(from: Data("Hello from UDP".utf8), to: addr!)
    #expect(bytesWritten == 14)

    // Close the socket...
    socket.close()
    #expect(!socket.isActive)
  }
  
  @Test func testCreateAddressUnix() {
    let addr = Socket.createAddress(for: "foobar.org", on: 1234, family: .unix)
    #expect(addr == nil)
  }

  @Test func testIsReadableWritableFail() throws {

    // Create the socket...
    let socket = try createHelper()

    defer {
      // Close the socket...
      socket.close()
      #expect(!socket.isActive)
    }

    do {
      // Expect this to fail with Socket.SOCKET_ERR_NOT_CONNECTED exception...
      _ = try socket.isReadableOrWritable()
      Issue.record("This should be unreachable")

    } catch let socketError as Socket.Error {

      print("testIsReadableWritableFail Error reported: \(socketError.description)")
      #expect(socketError.errorCode == Int32(Socket.SOCKET_ERR_NOT_CONNECTED))
    }
  }

  @Test func testIsReadableWritable() throws {

    // Create the socket..
    let socket = try createHelper()

    // Listen on the port...
    try socket.listen(on: Int(self.port), maxBacklogSize: 10)
    #expect(socket.isListening)
    #expect(socket.listeningPort == self.port)

    // Create a second socket...
    let socket2 = try createHelper()

    // Now attempt to connect to the listening socket...
    try socket2.connect(to: self.host, port: self.port)
    #expect(socket2.isConnected)

    // Test to see if it's readable or writable...
    var readable: Bool = false
    var writable: Bool = false
    (readable, writable) = try socket2.isReadableOrWritable()
    print("Socket2 is readable: \(readable), writable: \(writable)")

    // Socket should be writable but NOT readable...
    #expect(writable, "Socket 2 is not writable but should be...")
    #expect(!readable, "Socket 2 is readable and shouldn't be...")

    // Close the socket...
    socket.close()
    #expect(!socket.isActive)
    socket2.close()
    #expect(!socket2.isActive)
  }

  @Test func testFDSetBitFields() {
    var fdSet = fd_set()
    fdSet.zero()

    // The default number of max open file descriptors on Linux is 1024. On macOS,
    //	the default is unlimited.  I think checking for 1024 should be enough...
    
    // #expect does not work with mutating functions
    var result: Bool
    for i: Int32 in 0...1024 {
      fdSet.set(i)
      result = fdSet.isSet(i)
      #expect(result)
      
      fdSet.clear(i)
      result = fdSet.isSet(i)
      #expect(!result)
    }
  }

  @Test func testDomainSocketPath() throws {

    let okPath = "111111111111111111111111111111111"
    assert(okPath.utf8.count == 33)
    var sig = try Socket.Signature(socketType: .stream, proto: .unix, path: okPath)
    #expect(sig != nil)

    let problematicPath = okPath + "1"
    assert(problematicPath.utf8.count > 33)
    sig = try Socket.Signature(socketType: .stream, proto: .unix, path: problematicPath)
    #expect(sig != nil)
  }

  @Test func testReadWrite() throws {

    let hostname = "127.0.0.1"
    let port: Int32 = 1337

    var data = Data()

    // Launch the server helper...
    self.launchServerHelper()

    // Need to wait for the server to come up...
    self.sleep(2)

    // Create the signature...
    let signature = try Socket.Signature(
      protocolFamily: .inet,
      socketType: .stream,
      proto: .tcp,
      hostname: hostname,
      port: port
    )!

    // Create the socket...
    let socket = try createHelper()

    // Defer cleanup...
    defer {
      // Close the socket...
      socket.close()
      #expect(!socket.isActive)
    }

    // Connect to the server helper...
    try socket.connect(using: signature)
    if !socket.isConnected {

      fatalError("Failed to connect to the server...")
    }

    print("\nConnected to host: \(hostname):\(port)")
    print("\tSocket signature: \(socket.signature!.description)\n")

    _ = try self.readAndPrint(socket: socket, data: &data)

    let hello = "Hello from client..."
    try socket.write(from: hello)

    print("Wrote '\(hello)' to socket...")

    let response = try readAndPrint(socket: socket, data: &data)

    #expect(response != nil)
    #expect(response == "Server response: \n\(hello)\n")

    try socket.write(from: "QUIT")

    print("Sent quit to server...")

    // Need to wait for the server to go down before continuing...
    self.sleep(1)
  }

  @Test func testTruncateTCP() throws {

    let hostname = "127.0.0.1"
    let port: Int32 = 1337

    var data = Data()

    // Launch the server helper...
    self.launchServerHelper()

    // Need to wait for the server to come up...
    self.sleep(2)

    // Create the signature...
    let signature = try Socket.Signature(
      protocolFamily: .inet,
      socketType: .stream,
      proto: .tcp,
      hostname: hostname,
      port: port
    )!

    // Create the socket...
    let socket = try createHelper()

    // Defer cleanup...
    defer {
      // Close the socket...
      socket.close()
      #expect(!socket.isActive)
    }

    // Connect to the server helper...
    try socket.connect(using: signature)
    if !socket.isConnected {

      fatalError("Failed to connect to the server...")
    }

    print("\nConnected to host: \(hostname):\(port)")
    print("\tSocket signature: \(socket.signature!.description)\n")

    _ = try self.readAndPrint(socket: socket, data: &data)

    let hello = "Hello from client..."
    try socket.write(from: hello)

    print("Wrote '\(hello)' to socket...")

    let buf = UnsafeMutablePointer<CChar>.allocate(capacity: 19)
    buf.initialize(repeating: 0, count: 19)

    defer {
      buf.deinitialize(count: 19)
      buf.deallocate()
    }

    // Save room for a null character...
    _ = try socket.read(into: buf, bufSize: 18, truncate: true)
    let response = String(cString: buf)

    #expect(response == "Server response: \n")

    let response2 = try readAndPrint(socket: socket, data: &data)

    #expect(response2 == "\(hello)\n")

    try socket.write(from: "QUIT")

    print("Sent quit to server...")

    // Need to wait for the server to go down before continuing...
    self.sleep(1)
  }

  @Test func testReadWriteUDP() throws {

    let hostname = "127.0.0.1"
    let port: Int32 = 1337

    self.launchUDPHelper()

    // Need to wait for the helper to come up...
    self.sleep(2)

    let socket = try self.createUDPHelper()

    // Defer cleanup...
    defer {
      // Close the socket...
      socket.close()
      #expect(!socket.isActive)
    }

    let addr = Socket.createAddress(for: hostname, on: port)

    #expect(addr != nil)
    try socket.write(from: Data("Hello from UDP".utf8), to: addr!)

    var data = Data()
    var (_, address) = try socket.readDatagram(into: &data)

    guard let response = NSString(data: data, encoding: String.Encoding.utf8.rawValue) else {

      data.count = 0
      Issue.record("Error decoding response...")
      return
    }

    var (remoteHost, remotePort) = Socket.hostnameAndPort(from: address!)!
    print("Received from \(remoteHost):\(remotePort): \(response)\n")

    try socket.write(from: Data("Hello again".utf8), to: addr!)

    let buf = UnsafeMutablePointer<CChar>.allocate(capacity: 10)
    buf.initialize(repeating: 0, count: 10)

    defer {
      buf.deinitialize(count: 10)
      buf.deallocate()
    }

    // Save room for a null character...
    (_, address) = try socket.readDatagram(into: buf, bufSize: 9)

    let response2 = String(cString: buf)
    (remoteHost, remotePort) = Socket.hostnameAndPort(from: address!)!
    print("Received from \(remoteHost):\(remotePort): \(response2)\n")

    print("Sending quit to server...")
    try socket.write(from: Data("QUIT".utf8), to: addr!)

    // Need to wait for the server to go down before continuing...
    self.sleep(1)
  }

  @Test func testReadWriteUnix() throws {

    var data = Data()

    // Launch the server helper...
    self.launchServerHelper(family: .unix)

    // Need to wait for the server to come up...
    self.sleep(2)

    // Create the signature...
    let signature = try Socket.Signature(socketType: .stream, proto: .unix, path: self.path)!

    // Create the socket...
    let socket = try createHelper(family: .unix)

    // Defer cleanup...
    defer {
      // Close the socket...
      socket.close()
      #expect(!socket.isActive)
    }

    // Connect to the server helper...
    try socket.connect(using: signature)
    if !socket.isConnected {

      fatalError("Failed to connect to the server...")
    }

    print("\nConnected to path: \(self.path)")
    print("\tSocket signature: \(socket.signature!.description)\n")

    _ = try self.readAndPrint(socket: socket, data: &data)

    let hello = "Hello from client..."
    try socket.write(from: hello)

    print("Wrote '\(hello)' to socket...")

    let response = try readAndPrint(socket: socket, data: &data)

    #expect(response != nil)
    #expect(response! == "Server response: \n\(hello)\n")

    try socket.write(from: "QUIT")

    print("Sent quit to server...")

    // Need to wait for the server to go down before continuing...
    self.sleep(1)
  }
}
