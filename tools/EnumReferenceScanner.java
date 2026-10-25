import java.nio.file.*;
import java.util.*;
import java.util.jar.*;
import org.objectweb.asm.*;

/** Check enum constants explicitly; an unknown java.lang.Enum superclass
 * must not hide missing constants such as CAUGHT -> OWNED. */
public final class EnumReferenceScanner {
    public static void main(String[] args) throws Exception {
        Map<String,Set<String>> enums=new HashMap<>();
        try(JarFile jar=new JarFile(args[0])) {
            for(JarEntry e:jar.stream().filter(e->e.getName().endsWith(".class")).toList()) {
                new ClassReader(jar.getInputStream(e).readAllBytes()).accept(new ClassVisitor(Opcodes.ASM9){
                    String name;Set<String> fields;
                    public void visit(int v,int a,String n,String s,String p,String[] i){
                        name=n;if((a&Opcodes.ACC_ENUM)!=0){fields=new HashSet<>();enums.put(name,fields);}
                    }
                    public FieldVisitor visitField(int a,String n,String d,String s,Object v){if(fields!=null)fields.add(n+":"+d);return null;}
                },ClassReader.SKIP_CODE);
            }
        }
        List<String> findings=new ArrayList<>();
        try(var paths=Files.list(Path.of(args[1]))) {
            for(Path p:paths.filter(p->p.toString().endsWith(".jar")).toList()) {
                try(JarFile jar=new JarFile(p.toFile())) {
                    for(JarEntry e:jar.stream().filter(e->e.getName().endsWith(".class")).toList()) {
                        new ClassReader(jar.getInputStream(e).readAllBytes()).accept(new ClassVisitor(Opcodes.ASM9){
                            public MethodVisitor visitMethod(int a,String n,String d,String s,String[] ex){return new MethodVisitor(Opcodes.ASM9){
                                public void visitFieldInsn(int op,String owner,String name,String desc){
                                    Set<String> fields=enums.get(owner);
                                    if(op==Opcodes.GETSTATIC&&fields!=null&&!fields.contains(name+":"+desc))findings.add(p.getFileName()+"|"+e.getName()+"|"+owner+"."+name);
                                }
                            };}
                        },ClassReader.SKIP_DEBUG|ClassReader.SKIP_FRAMES);
                    }
                }
            }
        }
        new TreeSet<>(findings).forEach(System.out::println);
        System.out.println("missing_enum_constants="+findings.size());
        if(!findings.isEmpty())System.exit(1);
    }
}
