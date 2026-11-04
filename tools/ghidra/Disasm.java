// Dump disassembly. Usage: <listFile> <outFile>
//   listFile lines: <symtabVAhex> [count]   (default 60 instructions)
//   Also prints the containing function and its body ranges.
// @category IEX
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressRange;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;

import java.io.File;
import java.io.PrintWriter;
import java.nio.file.Files;

public class Disasm extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        long delta = currentProgram.getImageBase().getOffset();
        try (PrintWriter pw = new PrintWriter(new File(args[1]), "UTF-8")) {
            for (String raw : Files.readAllLines(new File(args[0]).toPath())) {
                String line = raw.trim();
                if (line.isEmpty() || line.startsWith("#")) continue;
                String[] p = line.split("\\s+");
                Address a = toAddr(Long.parseLong(p[0].replace("0x", ""), 16) + delta);
                int n = p.length > 1 ? Integer.parseInt(p[1]) : 60;
                Function f = getFunctionContaining(a);
                pw.println("=== " + p[0] + " in " + (f == null ? "?" : f.getName(true)));
                if (f != null) {
                    for (AddressRange r : f.getBody()) pw.println("  body " + r);
                }
                Instruction ins = getInstructionAt(a);
                if (ins == null) ins = getInstructionAfter(a);
                for (int i = 0; i < n && ins != null; i++) {
                    long va = ins.getAddress().getOffset() - delta;
                    pw.println(String.format("  %08x  %s", va, ins.toString()));
                    ins = ins.getNext();
                }
            }
        }
    }
}
