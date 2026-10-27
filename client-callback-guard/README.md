# Client callback guard for Cobblemon 1.8.3

This client-only MIT mod skips the held-item/cosmetic-item **server callback listeners** when the event Pokemon is a client instance or no integrated Minecraft server exists. It does not cancel the held-item event itself, item synchronization, or other listeners. Server Pokemon with an available server continue through the original callbacks.

The guarded methods are `CallbackHandler.setup$lambda$44` through `$47` from the exact installed Cobblemon 1.8.3 build. Fabric metadata restricts the dependency to `1.8.3+1.21.1`. A later Cobblemon release needs a fresh target audit.

On Windows with JDK 21, the existing Modrinth 1.21.1/Fabric installation, and Python 3:

```powershell
python tools/build-client-callback-guard.py
python tools/test-client-callback-guard.py
```

The build script reads compile dependencies from the installed integrated test profile and Modrinth cache. It writes the JAR and source ZIP under ignored `out/client-callback-guard/`. No Minecraft process is launched.

The harness runs the compiled pre/post guard methods with isolated API fixtures for all client/server availability combinations and verifies the four target signatures against the real installed Cobblemon JAR. This is not a full Mixin application or gameplay test; those remain pending.
