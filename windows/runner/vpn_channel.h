// windows/runner/vpn_channel.h
#pragma once
#include <flutter/plugin_registrar_windows.h>
#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/standard_method_codec.h>
#include <atomic>
#include <string>
#include <utility>
#include <memory>

namespace vpn_engine {

class VpnChannel : public flutter::Plugin {
public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);
  VpnChannel();
  virtual ~VpnChannel();

private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  bool connectWireGuard(const std::string& configStr);
  void disconnectWireGuard();
  std::pair<std::string,std::string> generateKeyPair();
  void startStatsThread();
  static int pingTcp(const std::string& host, int port);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> state_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> traffic_channel_;
};

} // namespace vpn_engine
