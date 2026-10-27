"""Run the real compiled guard methods with isolated API fixtures, not Minecraft."""
from pathlib import Path
import os,subprocess,json,re

repo=Path(__file__).resolve().parent.parent
out=repo/'out/client-callback-guard';fixture=out/'test-src';classes=out/'test-classes'
fixture.mkdir(exist_ok=True);classes.mkdir(exist_ok=True)
sources={
'com/cobblemon/mod/common/pokemon/Pokemon.java':'''package com.cobblemon.mod.common.pokemon;
public class Pokemon {public boolean client; public Pokemon(boolean c){client=c;} public boolean isClient$common(){return client;}}''',
'com/cobblemon/mod/common/api/events/pokemon/HeldItemEvent.java':'''package com.cobblemon.mod.common.api.events.pokemon;
import com.cobblemon.mod.common.pokemon.Pokemon;
public interface HeldItemEvent {
class Pre {private final Pokemon p;public Pre(Pokemon p){this.p=p;}public Pokemon getPokemon(){return p;}}
class Post {private final Pokemon p;public Post(Pokemon p){this.p=p;}public Pokemon getPokemon(){return p;}}
}''',
'net/minecraft/server/MinecraftServer.java':'''package net.minecraft.server;public class MinecraftServer {}''',
'com/cobblemon/mod/common/util/DistributionUtilsKt.java':'''package com.cobblemon.mod.common.util;
public class DistributionUtilsKt {public static boolean available;public static net.minecraft.server.MinecraftServer server(){return available?new net.minecraft.server.MinecraftServer():null;}}''',
'GuardHarness.java':'''import java.lang.reflect.*;
import com.cobblemon.mod.common.pokemon.Pokemon;
import com.cobblemon.mod.common.api.events.pokemon.HeldItemEvent;
import com.cobblemon.mod.common.util.DistributionUtilsKt;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;
public class GuardHarness {
public static void main(String[] args)throws Exception {
 Class<?> guard=Class.forName("kr.cobbleverse.clientfix.HeldItemCallbackGuardMixin");int checks=0;
 for(boolean client:new boolean[]{false,true})for(boolean server:new boolean[]{false,true}){
  DistributionUtilsKt.available=server;
  for(String type:new String[]{"Pre","Post"}){
   Class<?> event=Class.forName("com.cobblemon.mod.common.api.events.pokemon.HeldItemEvent$"+type);
   Object value=event.getConstructor(Pokemon.class).newInstance(new Pokemon(client));
   Method m=guard.getDeclaredMethod("guard"+type,event,CallbackInfoReturnable.class);m.setAccessible(true);
   CallbackInfoReturnable<kotlin.Unit> ci=new CallbackInfoReturnable<>("test",true);
   m.invoke(null,value,ci);
   if(ci.isCancelled()!=(client||!server))throw new AssertionError(type+" wrong side guard");
   if(ci.isCancelled()&&ci.getReturnValue()!=kotlin.Unit.INSTANCE)throw new AssertionError("Wrong Unit return");
   checks++;
  }
 }
 System.out.println("PASS: "+checks+" pre/post client/server callback cases; server callbacks preserved.");
}}
'''}
for name,text in sources.items():
    p=fixture/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text,encoding='utf8')
java_home=Path(os.environ.get('JAVA_HOME',r'C:\Program Files\Java\jdk-21.0.12'))/'bin'
meta=Path(os.environ['APPDATA'])/'ModrinthApp/meta'
mixin=next((meta/'libraries/net/fabricmc/sponge-mixin/0.17.0+mixin.0.8.7').glob('*.jar'))
cp=os.pathsep.join(map(str,[out/'cobbleverse-client-callback-guard-1.0.0.jar',out/'kotlin-stdlib.jar',mixin]))
subprocess.run([str(java_home/'javac.exe'),'--release','21','-proc:none','-classpath',cp,'-d',str(classes),*map(str,fixture.rglob('*.java'))],check=True)
subprocess.run([str(java_home/'java.exe'),'-Xverify:all','-cp',str(classes)+os.pathsep+cp,'GuardHarness'],check=True)
core=Path(os.environ['APPDATA'])/'ModrinthApp/profiles/COBBLEVERSE 1.8 Integrated Test/mods/Cobblemon-fabric-1.8.3+1.21.1.jar'
listing=subprocess.check_output([str(java_home/'javap.exe'),'-classpath',str(core),'-p','com.cobblemon.mod.common.events.CallbackHandler'],text=True)
for n,kind in [(44,'Pre'),(45,'Post'),(46,'Pre'),(47,'Post')]:
    assert f'setup$lambda${n}(com.cobblemon.mod.common.api.events.pokemon.HeldItemEvent${kind})' in listing
report={'guard_logic_cases':8,'jvm_bytecode_verification':'passed','four_real_mixin_target_signatures':'passed','minecraft_started':False,'real_client_runtime':'not tested'}
(repo/'integration/client-callback-guard-verification.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
print(json.dumps(report,indent=2))
