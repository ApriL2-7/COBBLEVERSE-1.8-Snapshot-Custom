import java.io.IOException;
import java.nio.file.*;
import java.util.*;
import java.util.jar.*;
import org.objectweb.asm.*;

public final class MegaApiLinkageScanner {
    record Member(String name, String desc) {}
    record ClassInfo(String superName, List<String> interfaces, Set<Member> methods, Set<Member> fields) {}
    enum Result { FOUND, MISSING, UNKNOWN }

    private static final Map<String, ClassInfo> classes = new HashMap<>();
    private static final Set<String> findings = new TreeSet<>();
    private static final Set<Member> objectMethods = Set.of(
            new Member("<init>", "()V"),
            new Member("hashCode", "()I"),
            new Member("equals", "(Ljava/lang/Object;)Z"),
            new Member("toString", "()Ljava/lang/String;"),
            new Member("getClass", "()Ljava/lang/Class;"),
            new Member("clone", "()Ljava/lang/Object;"),
            new Member("finalize", "()V"),
            new Member("notify", "()V"),
            new Member("notifyAll", "()V"),
            new Member("wait", "()V"),
            new Member("wait", "(J)V"),
            new Member("wait", "(JI)V")
    );

    public static void main(String[] args) throws Exception {
        if (args.length != 2) {
            System.err.println("usage: MegaApiLinkageScanner <cobblemon.jar> <mods-directory>");
            System.exit(2);
        }
        indexJar(Path.of(args[0]));
        try (var paths = Files.list(Path.of(args[1]))) {
            for (Path jar : paths.filter(p -> p.getFileName().toString().endsWith(".jar")).sorted().toList()) {
                if (!jar.toAbsolutePath().equals(Path.of(args[0]).toAbsolutePath())) scanJar(jar);
            }
        }
        System.out.println("finding_count=" + findings.size());
        findings.forEach(System.out::println);
    }

    private static void indexJar(Path jar) throws IOException {
        try (JarFile jf = new JarFile(jar.toFile())) {
            var entries = jf.entries();
            while (entries.hasMoreElements()) {
                JarEntry e = entries.nextElement();
                if (!e.getName().endsWith(".class")) continue;
                try (var in = jf.getInputStream(e)) {
                    new ClassReader(in).accept(new ClassVisitor(Opcodes.ASM9) {
                        String name, superName;
                        List<String> interfaces;
                        Set<Member> methods = new HashSet<>(), fields = new HashSet<>();
                        @Override public void visit(int v, int a, String n, String sig, String s, String[] is) {
                            name = n; superName = s; interfaces = is == null ? List.of() : List.of(is);
                        }
                        @Override public FieldVisitor visitField(int a, String n, String d, String s, Object val) {
                            fields.add(new Member(n, d)); return null;
                        }
                        @Override public MethodVisitor visitMethod(int a, String n, String d, String s, String[] ex) {
                            methods.add(new Member(n, d)); return null;
                        }
                        @Override public void visitEnd() {
                            classes.put(name, new ClassInfo(superName, interfaces, methods, fields));
                        }
                    }, ClassReader.SKIP_CODE | ClassReader.SKIP_DEBUG | ClassReader.SKIP_FRAMES);
                }
            }
        }
    }

    private static void scanJar(Path jar) {
        try (JarFile jf = new JarFile(jar.toFile())) {
            var entries = jf.entries();
            while (entries.hasMoreElements()) {
                JarEntry e = entries.nextElement();
                if (!e.getName().endsWith(".class") || e.getName().startsWith("com/github/yajatkaul/mega_showdown/")) continue;
                try (var in = jf.getInputStream(e)) {
                    scanClass(jar.getFileName().toString(), new ClassReader(in));
                } catch (Throwable t) {
                    System.err.println("scan_error=" + jar.getFileName() + "|" + e.getName() + "|" + t);
                }
            }
        } catch (Throwable t) {
            System.err.println("jar_error=" + jar + "|" + t);
        }
    }

    private static void scanClass(String jar, ClassReader reader) {
        reader.accept(new ClassVisitor(Opcodes.ASM9) {
            String sourceClass;
            @Override public void visit(int v, int a, String n, String sig, String s, String[] is) {
                sourceClass = n;
                checkType(jar, sourceClass, "class", s);
                if (is != null) for (String i : is) checkType(jar, sourceClass, "interface", i);
            }
            @Override public FieldVisitor visitField(int a, String n, String d, String s, Object val) {
                checkDesc(jar, sourceClass, "field_desc", d); return null;
            }
            @Override public MethodVisitor visitMethod(int a, String n, String d, String s, String[] ex) {
                checkMethodDesc(jar, sourceClass, "method_desc", d);
                return new MethodVisitor(Opcodes.ASM9) {
                    int line = -1;
                    @Override public void visitLineNumber(int l, Label start) { line = l; }
                    @Override public void visitTypeInsn(int opcode, String type) { checkType(jar, sourceClass, loc("type", line), type); }
                    @Override public void visitFieldInsn(int opcode, String owner, String name, String desc) {
                        checkType(jar, sourceClass, loc("field_owner", line), owner);
                        if (isCobble(owner) && classes.containsKey(owner) && resolveField(owner, new Member(name, desc), new HashSet<>()) == Result.MISSING)
                            add(jar, sourceClass, loc("missing_field", line), owner, name, desc);
                        checkDesc(jar, sourceClass, loc("field_ref_desc", line), desc);
                    }
                    @Override public void visitMethodInsn(int opcode, String owner, String name, String desc, boolean itf) {
                        checkType(jar, sourceClass, loc("method_owner", line), owner);
                        if (isCobble(owner) && classes.containsKey(owner) && resolveMethod(owner, new Member(name, desc), new HashSet<>()) == Result.MISSING)
                            add(jar, sourceClass, loc("missing_method", line), owner, name, desc);
                        checkMethodDesc(jar, sourceClass, loc("method_ref_desc", line), desc);
                    }
                    @Override public void visitLdcInsn(Object value) {
                        if (value instanceof Type t) checkAsmType(jar, sourceClass, loc("ldc_type", line), t);
                    }
                    @Override public void visitInvokeDynamicInsn(String name, String desc, Handle bsm, Object... args) {
                        checkMethodDesc(jar, sourceClass, loc("indy_desc", line), desc);
                        checkHandle(jar, sourceClass, line, bsm);
                        for (Object arg : args) {
                            if (arg instanceof Handle h) checkHandle(jar, sourceClass, line, h);
                            else if (arg instanceof Type t) checkAsmType(jar, sourceClass, loc("indy_type", line), t);
                        }
                    }
                };
            }
        }, ClassReader.SKIP_FRAMES);
    }

    private static void checkHandle(String jar, String src, int line, Handle h) {
        String owner = h.getOwner();
        checkType(jar, src, loc("handle_owner", line), owner);
        if (!isCobble(owner) || !classes.containsKey(owner)) return;
        Member m = new Member(h.getName(), h.getDesc());
        boolean field = h.getTag() >= Opcodes.H_GETFIELD && h.getTag() <= Opcodes.H_PUTSTATIC;
        Result result = field ? resolveField(owner, m, new HashSet<>()) : resolveMethod(owner, m, new HashSet<>());
        if (result == Result.MISSING) add(jar, src, loc(field ? "missing_field_handle" : "missing_method_handle", line), owner, h.getName(), h.getDesc());
    }

    private static Result resolveMethod(String owner, Member target, Set<String> seen) {
        if (owner == null) return Result.MISSING;
        if (owner.equals("java/lang/Object")) return objectMethods.contains(target) ? Result.FOUND : Result.MISSING;
        if (!seen.add(owner)) return Result.MISSING;
        ClassInfo c = classes.get(owner);
        if (c == null) return Result.UNKNOWN;
        if (c.methods.contains(target)) return Result.FOUND;
        boolean unknown = false;
        Result r = resolveMethod(c.superName, target, seen);
        if (r == Result.FOUND) return r;
        unknown |= r == Result.UNKNOWN;
        for (String i : c.interfaces) {
            r = resolveMethod(i, target, seen);
            if (r == Result.FOUND) return r;
            unknown |= r == Result.UNKNOWN;
        }
        return unknown ? Result.UNKNOWN : Result.MISSING;
    }

    private static Result resolveField(String owner, Member target, Set<String> seen) {
        if (owner == null || owner.equals("java/lang/Object")) return Result.MISSING;
        if (!seen.add(owner)) return Result.MISSING;
        ClassInfo c = classes.get(owner);
        if (c == null) return Result.UNKNOWN;
        if (c.fields.contains(target)) return Result.FOUND;
        boolean unknown = false;
        Result r = resolveField(c.superName, target, seen);
        if (r == Result.FOUND) return r;
        unknown |= r == Result.UNKNOWN;
        for (String i : c.interfaces) {
            r = resolveField(i, target, seen);
            if (r == Result.FOUND) return r;
            unknown |= r == Result.UNKNOWN;
        }
        return unknown ? Result.UNKNOWN : Result.MISSING;
    }

    private static void checkDesc(String jar, String src, String kind, String desc) {
        checkAsmType(jar, src, kind, Type.getType(desc));
    }
    private static void checkMethodDesc(String jar, String src, String kind, String desc) {
        Type mt = Type.getMethodType(desc);
        checkAsmType(jar, src, kind, mt.getReturnType());
        for (Type t : mt.getArgumentTypes()) checkAsmType(jar, src, kind, t);
    }
    private static void checkAsmType(String jar, String src, String kind, Type t) {
        if (t.getSort() == Type.ARRAY) t = t.getElementType();
        if (t.getSort() == Type.OBJECT) checkType(jar, src, kind, t.getInternalName());
        else if (t.getSort() == Type.METHOD) {
            checkAsmType(jar, src, kind, t.getReturnType());
            for (Type a : t.getArgumentTypes()) checkAsmType(jar, src, kind, a);
        }
    }
    private static void checkType(String jar, String src, String kind, String type) {
        if (isCobble(type) && !classes.containsKey(type)) add(jar, src, "missing_type_" + kind, type, "", "");
    }
    private static boolean isCobble(String n) { return n != null && n.startsWith("com/github/yajatkaul/mega_showdown/"); }
    private static String loc(String kind, int line) { return line < 0 ? kind : kind + "@" + line; }
    private static void add(String jar, String src, String kind, String owner, String name, String desc) {
        findings.add(String.join("|", jar, src, kind, owner, name, desc));
    }
}
