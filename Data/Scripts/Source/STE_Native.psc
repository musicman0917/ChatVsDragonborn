Scriptname STE_Native
{
  Native function declarations implemented in
  SKSEPlugin/src/Papyrus/ChaosNativeFunctions.cpp and registered under this
  script name via RE::BSScript::IVirtualMachine::RegisterFunction. This file
  has no bodies — it only lets the Papyrus compiler resolve calls like
  STE_Native.PollNextCommand() from SkyrimChaosRouter.psc.
}

; Pops the next queued chaos command (FIFO) or returns an empty array if none
; is waiting. Layout: [id, type, viewer, price] — see
; SKSEPlugin/src/Papyrus/ChaosNativeFunctions.cpp for details.
string[] Function PollNextCommand() global native

; Reads a single integer arg (e.g. "count", "amount") out of whichever
; command PollNextCommand most recently popped. No JSON parsing happens in
; Papyrus — the plugin already has the args parsed and just hands back the
; requested value.
int Function GetCommandArgInt(string key, int missingValue) global native

; Reports the outcome of executing a command back to TwitchBridge (toast +
; refund-on-failure handling live on the bridge side).
Function ReportCommandResult(string id, bool success, string message) global native

; Live-editable settings backing the MCM menu (Data/MCM/Config/SkyrimTwitchExpansion).
string Function GetSetting(string key) global native
Function SetSetting(string key, string value) global native
int Function GetSettingInt(string key, int missingValue) global native
