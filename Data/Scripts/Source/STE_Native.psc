Scriptname STE_Native
{
  Native function declarations implemented in
  SKSEPlugin/src/Papyrus/ChaosNativeFunctions.cpp and registered under this
  script name via RE::BSScript::IVirtualMachine::RegisterFunction. This file
  has no bodies — it only lets the Papyrus compiler resolve calls like
  STE_Native.PollNextCommand() from SkyrimChaosRouter.psc.
}

; Pops the next queued chaos command (FIFO) or returns an empty array if none
; is waiting. Layout: [id, type, viewer, price, argsJson] — see
; SKSEPlugin/src/Papyrus/ChaosNativeFunctions.cpp for details.
string[] Function PollNextCommand() global native

; Reports the outcome of executing a command back to TwitchBridge (toast +
; refund-on-failure handling live on the bridge side).
Function ReportCommandResult(string id, bool success, string message) global native

; Live-editable settings backing the MCM menu (Data/MCM/Config/SkyrimTwitchExpansion).
string Function GetSetting(string key) global native
Function SetSetting(string key, string value) global native
