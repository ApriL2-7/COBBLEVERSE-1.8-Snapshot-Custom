import java.nio.file.*;
import java.util.jar.*;
import org.objectweb.asm.*;

/** Local-only adaptation of Battle Tower 1.11.23 to Cobblemon API119.
 * The caller verifies the input against the official Modrinth download hash.
 * No third-party binary is published by this repository.
 */
public final class BattleTowerApi119Patcher {
    static int constructors, afterDispatches;
    public static void main(String[] args) throws Exception {
        if (args.length != 2) throw new IllegalArgumentException("input.jar output.jar");
        Path input=Path.of(args[0]), output=Path.of(args[1]);
        if (Files.exists(output)) throw new IllegalArgumentException("Output already exists");
        try (JarFile jar=new JarFile(input.toFile()); JarOutputStream out=new JarOutputStream(Files.newOutputStream(output))) {
            for (JarEntry entry:jar.stream().toList()) {
                byte[] bytes=jar.getInputStream(entry).readAllBytes();
                if (entry.getName().equals("battle/tower/BattleTower.class") || entry.getName().equals("battle/tower/battle/BattleTowerManager.class")) {
                    ClassReader reader=new ClassReader(bytes);
                    ClassWriter writer=new ClassWriter(reader,ClassWriter.COMPUTE_MAXS);
                    reader.accept(new ClassVisitor(Opcodes.ASM9,writer) {
                        @Override public MethodVisitor visitMethod(int a,String n,String d,String s,String[] e) {
                            return new MethodVisitor(Opcodes.ASM9,super.visitMethod(a,n,d,s,e)) {
                                @Override public void visitMethodInsn(int op,String owner,String name,String desc,boolean itf) {
                                    if (owner.equals("com/cobblemon/mod/common/api/moves/MoveTemplate") && name.equals("<init>") && desc.endsWith("[Ljava/lang/Double;)V")) {
                                        // Moves.reload uses weight 50.0f when no move_weights entry exists.
                                        super.visitLdcInsn(50.0f);
                                        desc=desc.substring(0,desc.length()-2)+"F)V";
                                        constructors++;
                                    }
                                    if (owner.equals("com/cobblemon/mod/common/api/battles/model/PokemonBattle") && name.equals("getAfterDispatches") && desc.equals("()Ljava/util/List;")) {
                                        // API119 has only dispatches, already checked by the caller.
                                        // No secondary after-dispatch queue exists in this API.
                                        super.visitInsn(Opcodes.POP);
                                        super.visitMethodInsn(Opcodes.INVOKESTATIC,"java/util/Collections","emptyList","()Ljava/util/List;",false);
                                        afterDispatches++;
                                        return;
                                    }
                                    super.visitMethodInsn(op,owner,name,desc,itf);
                                }
                            };
                        }
                    },0);
                    bytes=writer.toByteArray();
                }
                JarEntry copy=new JarEntry(entry.getName()); copy.setTime(entry.getTime());
                out.putNextEntry(copy);out.write(bytes);out.closeEntry();
            }
        }
        if (constructors!=1 || afterDispatches!=2) {
            Files.delete(output);
            throw new IllegalStateException("Unexpected bytecode: constructors="+constructors+", afterDispatches="+afterDispatches);
        }
        System.out.println("Patched 1 constructor and 2 after-dispatch queue probes");
    }
}
