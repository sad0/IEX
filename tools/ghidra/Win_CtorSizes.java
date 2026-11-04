// Windows (MSVC x64) variant of CtorSizes: estimate sizeof(T) from "operator new(N)" before ctor calls.
// Usage (headless postScript args): <listFile> <outFile> <operatorNewRVA>
//   listFile lines: <label> <ctorRVA>[,<ctorRVA>...]   (image-relative, hex)
//   For each call site of a ctor, walks back (same function, max 60 instructions) to the nearest
//   CALL to operator new and reads the immediate loaded into ECX/RCX before it (MSVC x64 ABI:
//   first argument in RCX). Output lines: <label> size=0x.. caller=<func>@<rva>
//   Also lists, for the label "*", every operator new call with a constant size (histogram input).
// @category IEX
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.scalar.Scalar;
import ghidra.program.model.symbol.Reference;

import java.io.File;
import java.io.PrintWriter;
import java.nio.file.Files;
import java.util.List;

public class Win_CtorSizes extends GhidraScript {
    private long base;
    private Address opNew;

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 3) {
            printerr("args: <listFile> <outFile> <operatorNewRVA>");
            return;
        }
        base = currentProgram.getImageBase().getOffset();
        opNew = rva(Long.decode(args[2]));
        List<String> lines = Files.readAllLines(new File(args[0]).toPath());
        try (PrintWriter pw = new PrintWriter(new File(args[1]), "UTF-8")) {
            for (String raw : lines) {
                String line = raw.trim();
                if (line.isEmpty() || line.startsWith("#")) continue;
                String[] p = line.split("\\s+");
                String label = p[0];
                int hits = 0;
                for (String a : p[1].split(",")) {
                    Address ctor = rva(Long.decode(a));
                    for (Reference r : getReferencesTo(ctor)) {
                        if (!r.getReferenceType().isCall() && !r.getReferenceType().isJump()) continue;
                        Address site = r.getFromAddress();
                        Function f = getFunctionContaining(site);
                        pw.println(label + " " + scan(site) + " caller=" + (f == null ? "?" : f.getName())
                                + "@0x" + Long.toHexString(site.getOffset() - base));
                        hits++;
                    }
                }
                if (hits == 0) pw.println(label + " NO_CALLERS");
            }
        }
    }

    private Address rva(long v) {
        return currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(base + v);
    }

    private String scan(Address site) {
        Instruction ins = getInstructionAt(site);
        Function fn = getFunctionContaining(site);
        boolean sawNew = false;
        for (int i = 0; i < 60 && ins != null; i++) {
            ins = ins.getPrevious();
            if (ins == null) break;
            if (fn != null && !fn.getBody().contains(ins.getAddress())) break;
            String m = ins.getMnemonicString();
            if (!sawNew && m.equals("CALL")) {
                Address[] flows = ins.getFlows();
                if (flows.length > 0 && flows[0].equals(opNew)) sawNew = true;
                continue;
            }
            if (sawNew && m.equals("MOV")) {
                String op0 = ins.getDefaultOperandRepresentation(0);
                if (op0.equals("ECX") || op0.equals("RCX")) {
                    Object[] o = ins.getOpObjects(1);
                    if (o.length == 1 && o[0] instanceof Scalar) {
                        return "size=0x" + Long.toHexString(((Scalar) o[0]).getUnsignedValue());
                    }
                    return "size=? (ECX from " + ins.getDefaultOperandRepresentation(1) + ")";
                }
            }
        }
        return sawNew ? "size=? (no imm)" : "size=? (no new)";
    }
}
