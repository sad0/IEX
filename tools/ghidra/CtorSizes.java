// Estimate sizeof(T) from "operator new(N)" calls that precede calls to T's constructor.
// Usage (headless postScript args): <listFile> <outFile>
//   listFile lines: <label> <ctorAddrHex>[,<ctorAddrHex>...]
//   For each call site of a ctor, walks back (same function, max 40 instructions) to the
//   nearest call to operator new (_Znwm / _Znam) and reads the immediate loaded into EDI/RDI.
//   Output lines: <label> size=0x.. caller=<func>@<addr>
// @category IEX
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.scalar.Scalar;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.Symbol;

import java.io.File;
import java.io.PrintWriter;
import java.nio.file.Files;
import java.util.List;

public class CtorSizes extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        List<String> lines = Files.readAllLines(new File(args[0]).toPath());
        try (PrintWriter pw = new PrintWriter(new File(args[1]), "UTF-8")) {
            for (String raw : lines) {
                String line = raw.trim();
                if (line.isEmpty() || line.startsWith("#")) continue;
                String[] p = line.split("\\s+");
                String label = p[0];
                int hits = 0;
                for (String a : p[1].split(",")) {
                    Address ctor = toAddr(Long.parseLong(a.replace("0x", ""), 16) + symtabDelta());
                    for (Reference r : getReferencesTo(ctor)) {
                        if (!r.getReferenceType().isCall()) continue;
                        Address site = r.getFromAddress();
                        String res = scan(site);
                        Function f = getFunctionContaining(site);
                        pw.println(label + " " + res + " caller=" + (f == null ? "?" : f.getName(true)) + "@" + site);
                        hits++;
                    }
                }
                if (hits == 0) pw.println(label + " NO_CALLERS");
            }
        }
    }

    private String scan(Address site) {
        Instruction ins = getInstructionAt(site);
        Function fn = getFunctionContaining(site);
        boolean sawNew = false;
        for (int i = 0; i < 40 && ins != null; i++) {
            ins = ins.getPrevious();
            if (ins == null) break;
            if (fn != null && !fn.getBody().contains(ins.getAddress())) break;
            String m = ins.getMnemonicString();
            if (!sawNew && m.equals("CALL")) {
                Address[] flows = ins.getFlows();
                if (flows.length > 0) {
                    Symbol s = getSymbolAt(flows[0]);
                    String n = s == null ? "" : s.getName();
                    if (n.startsWith("_Znwm") || n.startsWith("_Znam") || n.contains("operator.new") || n.equals("operator_new")) {
                        sawNew = true;
                        continue;
                    }
                    // another call between new and ctor is fine, keep going
                }
            }
            if (sawNew && m.equals("MOV")) {
                String op0 = ins.getDefaultOperandRepresentation(0);
                if (op0.equals("EDI") || op0.equals("RDI")) {
                    Object[] o = ins.getOpObjects(1);
                    if (o.length == 1 && o[0] instanceof Scalar) {
                        return "size=0x" + Long.toHexString(((Scalar) o[0]).getUnsignedValue());
                    }
                    return "size=? (EDI from " + ins.getDefaultOperandRepresentation(1) + ")";
                }
            }
        }
        return sawNew ? "size=? (no imm)" : "size=? (no new)";
    }

    // Addresses in our list files are ELF symtab VAs (PIE, base 0). Ghidra loads PIE at its image
    // base (0x100000 by default), so add that delta.
    private long symtabDelta() {
        return currentProgram.getImageBase().getOffset();
    }
}
