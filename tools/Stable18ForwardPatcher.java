import java.nio.file.*;
import java.util.*;
import java.util.jar.*;
import org.objectweb.asm.*;

/** Preserve existing custom fixes while adapting field descriptors to 1.8.3. */
public final class Stable18ForwardPatcher {
    static final String OLD_ITEM="com/cobblemon/mod/common/item/CobblemonItem";
    static final String ITEM="net/minecraft/class_1792";
    static final String MEMORY="com/github/yajatkaul/mega_showdown/client/battle/storage/BattlePokemonMemory";
    static final String OLD_SET="(L"+OLD_ITEM+";)V";
    static final String NEW_SET="(L"+ITEM+";)V";
    public static void main(String[] args) throws Exception {
        if(args.length!=3)throw new IllegalArgumentException("stable-cobblemon.jar input.jar output.jar");
        Map<String,String> fields=new HashMap<>();
        try(JarFile stable=new JarFile(args[0])) {
            byte[] bytes=stable.getInputStream(stable.getJarEntry("com/cobblemon/mod/common/CobblemonItems.class")).readAllBytes();
            new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9) {
                public FieldVisitor visitField(int a,String n,String d,String s,Object v){fields.put(n,d);return null;}
            },ClassReader.SKIP_CODE);
        }
        int[] changes={0,0};
        Path output=Path.of(args[2]);
        if(Files.exists(output))throw new IllegalArgumentException("Output exists");
        try(JarFile input=new JarFile(args[1]);JarOutputStream out=new JarOutputStream(Files.newOutputStream(output))) {
            for(JarEntry entry:input.stream().toList()) {
                byte[] bytes=input.getInputStream(entry).readAllBytes();
                if(entry.getName().endsWith(".class")) {
                    ClassReader reader=new ClassReader(bytes);
                    ClassWriter writer=new ClassWriter(reader,ClassWriter.COMPUTE_MAXS);
                    reader.accept(new ClassVisitor(Opcodes.ASM9,writer){
                        public MethodVisitor visitMethod(int a,String n,String d,String s,String[] ex){
                            if(entry.getName().equals(MEMORY+".class") && n.equals("setItem") && d.equals(OLD_SET))d=NEW_SET;
                            return new MethodVisitor(Opcodes.ASM9,super.visitMethod(a,n,d,s,ex)) {
                                public void visitFrame(int type,int nl,Object[] local,int ns,Object[] stack){
                                    if(local!=null)for(int i=0;i<nl;i++)if(OLD_ITEM.equals(local[i]))local[i]=ITEM;
                                    if(stack!=null)for(int i=0;i<ns;i++)if(OLD_ITEM.equals(stack[i]))stack[i]=ITEM;
                                    super.visitFrame(type,nl,local,ns,stack);
                                }
                                public void visitFieldInsn(int op,String owner,String name,String desc){
                                    if(owner.equals("com/cobblemon/mod/common/api/pokedex/PokedexEntryProgress")) {
                                        if(name.equals("CAUGHT")){name="OWNED";changes[0]++;}
                                        if(name.equals("ENCOUNTERED")){name="SEEN";changes[0]++;}
                                        if(name.equals("NONE")){name="UNREGISTERED";changes[0]++;}
                                    }
                                    if(owner.equals("com/cobblemon/mod/common/CobblemonItems") && fields.containsKey(name) && !desc.equals(fields.get(name))) {
                                        System.out.println(entry.getName()+" field "+name+" "+desc+" -> "+fields.get(name));
                                        desc=fields.get(name);changes[0]++;
                                    }
                                    super.visitFieldInsn(op,owner,name,desc);
                                }
                                public void visitMethodInsn(int op,String owner,String name,String desc,boolean itf){
                                    if(owner.equals(MEMORY) && name.equals("setItem") && desc.equals(OLD_SET))desc=NEW_SET;
                                    // CobblemonItem only declares its constructor. All other
                                    // invoked methods belong to Item and accept newer item subclasses.
                                    if(owner.equals(OLD_ITEM) && !name.equals("<init>"))owner=ITEM;
                                    if(owner.equals("com/cobblemon/mod/common/api/types/ElementalType") && name.equals("<init>") && desc.equals("(Ljava/lang/String;Lnet/minecraft/class_5250;IIIILnet/minecraft/class_2960;Ljava/lang/String;Lnet/minecraft/class_2960;)V")) {
                                        // Invoke Kotlin's default constructor: use the official default
                                        // for the newly added tenth parameter (mask bit 9).
                                        super.visitInsn(Opcodes.ICONST_0);
                                        super.visitIntInsn(Opcodes.SIPUSH,512);
                                        super.visitInsn(Opcodes.ACONST_NULL);
                                        desc=desc.substring(0,desc.length()-2)+"IILkotlin/jvm/internal/DefaultConstructorMarker;)V";
                                        changes[1]++;
                                    }
                                    super.visitMethodInsn(op,owner,name,desc,itf);
                                }
                            };
                        }
                    },0);
                    bytes=writer.toByteArray();
                }
                JarEntry copy=new JarEntry(entry.getName());copy.setTime(entry.getTime());
                out.putNextEntry(copy);out.write(bytes);out.closeEntry();
            }
        }
        System.out.println("Adjusted field references="+changes[0]+", type constructors="+changes[1]);
    }
}
