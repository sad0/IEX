// Decompile a list of functions to text files.
// Usage (headless postScript args): <listFile> <outDir>  (hex addresses = ELF symtab VAs)
//   listFile: one entry per line, either a hex address (0x1234) or a symbol name
//   (mangled or Ghidra-demangled, e.g. CGameSprite::GetName). Lines starting with # are ignored.
//   Output: <outDir>/<addr>_<sanitized name>.c
// @category IEX
import ghidra.app.cmd.function.CreateFunctionCmd;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileOptions;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolIterator;

import java.io.File;
import java.io.PrintWriter;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.List;

public class DecompileList extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            printerr("args: <listFile> <outDir>");
            return;
        }
        List<String> lines = Files.readAllLines(new File(args[0]).toPath());
        File outDir = new File(args[1]);
        outDir.mkdirs();

        DecompInterface di = new DecompInterface();
        DecompileOptions opts = new DecompileOptions();
        di.setOptions(opts);
        di.toggleCCode(true);
        di.toggleSyntaxTree(false);
        di.openProgram(currentProgram);

        for (String raw : lines) {
            String line = raw.trim();
            if (line.isEmpty() || line.startsWith("#")) continue;
            for (Function f : resolve(line)) {
                if (monitor.isCancelled()) return;
                int fixedCalls = repairFlow(f);
                if (fixedCalls > 0) println("repaired " + fixedCalls + " call fall-throughs in " + f.getName(true));
                DecompileResults r = di.decompileFunction(f, 120, monitor);
                String name = f.getName(true);
                String safe = name.replaceAll("[^A-Za-z0-9_]+", "_");
                if (safe.length() > 120) safe = safe.substring(0, 120);
                String va = Long.toHexString(f.getEntryPoint().getOffset() - symtabDelta());
                File out = new File(outDir, va + "_" + safe + ".c");
                try (PrintWriter pw = new PrintWriter(out, "UTF-8")) {
                    pw.println("// " + name + " @ symtab VA 0x" + va + " (ghidra " + f.getEntryPoint() + ")");
                    if (r != null && r.decompileCompleted()) {
                        pw.println(r.getDecompiledFunction().getC());
                    } else {
                        pw.println("// DECOMPILE FAILED: " + (r == null ? "null" : r.getErrorMessage()));
                    }
                }
                println("decompiled " + name + " -> " + out.getName());
            }
        }
        di.dispose();
    }

    private List<Function> resolve(String key) {
        List<Function> out = new ArrayList<>();
        if (key.startsWith("0x") || key.startsWith("0X")) {
            Address a = toAddr(Long.parseLong(key.substring(2), 16) + symtabDelta());
            Function f = getFunctionAt(a);
            if (f == null) f = getFunctionContaining(a);
            if (f != null) out.add(f);
            else printerr("no function at " + key);
            return out;
        }
        SymbolIterator it = currentProgram.getSymbolTable().getSymbols(key);
        while (it.hasNext()) addSym(out, it.next());
        if (out.isEmpty()) {
            // qualified name: Class::Method
            for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
                if (f.getName(true).equals(key)) out.add(f);
            }
        }
        if (out.isEmpty()) printerr("not found: " + key);
        return out;
    }

    private void addSym(List<Function> out, Symbol s) {
        Function f = getFunctionAt(s.getAddress());
        if (f != null && !out.contains(f)) out.add(f);
    }

    // Auto-analysis left many CALLs without a fall-through (code after the call undisassembled),
    // which truncates decompilation. Walk the function's flow from its entry, disassemble missing
    // fall-throughs after CALLs, then recompute the body. In-memory only with -readOnly.
    private int repairFlow(Function f) {
        int fixedCalls = 0;
        java.util.ArrayDeque<Address> work = new java.util.ArrayDeque<>();
        java.util.HashSet<Address> seen = new java.util.HashSet<>();
        work.add(f.getEntryPoint());
        int budget = 200000;
        while (!work.isEmpty() && budget-- > 0) {
            Address a = work.poll();
            if (!seen.add(a)) continue;
            Instruction ins = getInstructionAt(a);
            if (ins == null) {
                disassemble(a);
                ins = getInstructionAt(a);
                if (ins == null) continue;
            }
            Function other = getFunctionAt(a);
            if (other != null && !other.equals(f)) {
                if (other.getName().startsWith("FUN_")) removeFunction(other);
                else continue;
            }
            String m = ins.getMnemonicString();
            if (m.equals("CALL")) {
                Address ft = ins.getMaxAddress().next();
                if (ins.getFallThrough() == null) {
                    ins.setFlowOverride(ghidra.program.model.listing.FlowOverride.NONE);
                    ins.setFallThrough(ft);
                    fixedCalls++;
                }
                work.add(ft);
                continue;
            }
            for (Address t : ins.getFlows()) {
                if (f.getBody().contains(t) || getFunctionAt(t) == null) work.add(t);
            }
            Address ft = ins.getFallThrough();
            if (ft != null) work.add(ft);
        }
        if (fixedCalls > 0) {
            try {
                CreateFunctionCmd.fixupFunctionBody(currentProgram, f, monitor);
            } catch (Exception e) {
                printerr("fixup failed for " + f.getName(true) + ": " + e.getMessage());
            }
        }
        return fixedCalls;
    }

    // Addresses in our list files are ELF symtab VAs (PIE, base 0). Ghidra loads PIE at its image
    // base (0x100000 by default), so add that delta.
    private long symtabDelta() {
        return currentProgram.getImageBase().getOffset();
    }
}
