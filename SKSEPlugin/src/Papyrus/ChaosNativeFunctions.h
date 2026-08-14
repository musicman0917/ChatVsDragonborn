#pragma once

namespace STE::Papyrus
{
    // Native functions exposed to Data/Scripts/Source/SkyrimChaosRouter.psc
    // (Papyrus global namespace "STE_Native"). These are the only points
    // where Papyrus and the C++ plugin talk to each other; everything else
    // (Twitch, IPC) is upstream of the MessageQueue these read/write.
    bool Register(RE::BSScript::IVirtualMachine* vm);
}
