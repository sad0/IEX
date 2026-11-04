// List the references to functions: call / jump sites with the containing function.
// Usage (headless postScript args): <listFile> <outFile>
//   listFile: one hex address per line (ELF symtab VA on Linux, image-relative RVA on Windows), optional label.
//   Output lines: "<target> <label>" then "  <site rva> <CALL|JMP|DATA> in <function @ entry rva>".
// @category IEX
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.symbol.Reference;

import java.io.File;
import java.io.PrintWriter;
import java.nio.file.Files;

public class Callers extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        long base = currentProgram.getImageBase().getOffset();
        try (PrintWriter pw = new PrintWriter(new File(args[1]), "UTF-8")) {
            for (String raw : Files.readAllLines(new File(args[0]).toPath())) {
                String line = raw.trim();
                if (line.isEmpty() || line.startsWith("#")) continue;
                String[] p = line.split("\\s+", 2);
                long rva = Long.decode(p[0]);
                Address a = toAddr(base + rva);
                pw.println(p[0] + " " + (p.length > 1 ? p[1] : ""));
                for (Reference r : getReferencesTo(a)) {
                    Address from = r.getFromAddress();
                    Instruction ins = getInstructionAt(from);
                    String kind = ins == null ? "DATA" : ins.getMnemonicString();
                    Function f = getFunctionContaining(from);
                    pw.println(String.format("  0x%x %s in %s", from.getOffset() - base, kind,
                            f == null ? "?" : f.getName(true) + " @ 0x" + Long.toHexString(f.getEntryPoint().getOffset() - base)));
                }
            }
        }
    }
}
