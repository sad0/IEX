// Export function boundaries, Ghidra-derived names (RTTI etc.) and vtable labels to JSON lines.
// Usage (headless postScript args): <outFile>
//   Each line: {"k":"fn","rva":"..","name":"..","ns":"..","thunk":"rva|null","ranges":[[start,end],...]}
//              {"k":"sym","rva":"..","name":"..","ns":".."}   (vftable / RTTI labels)
//   RVAs are relative to the program image base.
// @category IEX
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressRange;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolIterator;

import java.io.PrintWriter;

public class Win_ExportFunctions extends GhidraScript {
    private long base;

    private String rva(Address a) {
        return "0x" + Long.toHexString(a.getOffset() - base);
    }

    private static String esc(String s) {
        StringBuilder b = new StringBuilder();
        for (char c : s.toCharArray()) {
            if (c == '"' || c == '\\') b.append('\\').append(c);
            else if (c < 0x20) b.append(String.format("\\u%04x", (int) c));
            else b.append(c);
        }
        return b.toString();
    }

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 1) {
            printerr("args: <outFile>");
            return;
        }
        base = currentProgram.getImageBase().getOffset();
        int nf = 0, ns = 0;
        try (PrintWriter pw = new PrintWriter(args[0], "UTF-8")) {
            FunctionIterator it = currentProgram.getFunctionManager().getFunctions(true);
            while (it.hasNext()) {
                Function f = it.next();
                StringBuilder sb = new StringBuilder();
                sb.append("{\"k\":\"fn\",\"rva\":\"").append(rva(f.getEntryPoint())).append("\"");
                sb.append(",\"name\":\"").append(esc(f.getName())).append("\"");
                sb.append(",\"ns\":\"").append(esc(f.getParentNamespace().getName(true))).append("\"");
                Function t = f.isThunk() ? f.getThunkedFunction(false) : null;
                sb.append(",\"thunk\":").append(t == null ? "null" : "\"" + rva(t.getEntryPoint()) + "\"");
                if (f.isExternal()) sb.append(",\"ext\":true");
                sb.append(",\"ranges\":[");
                boolean first = true;
                for (AddressRange r : f.getBody()) {
                    if (!first) sb.append(',');
                    first = false;
                    sb.append("[\"").append(rva(r.getMinAddress())).append("\",\"").append(rva(r.getMaxAddress())).append("\"]");
                }
                sb.append("]}");
                pw.println(sb);
                nf++;
            }
            SymbolIterator si = currentProgram.getSymbolTable().getAllSymbols(false);
            while (si.hasNext()) {
                Symbol s = si.next();
                String n = s.getName();
                if (!(n.contains("vftable") || n.startsWith("RTTI_") || n.contains("vbtable"))) continue;
                pw.println("{\"k\":\"sym\",\"rva\":\"" + rva(s.getAddress()) + "\",\"name\":\"" + esc(n)
                        + "\",\"ns\":\"" + esc(s.getParentNamespace().getName(true)) + "\"}");
                ns++;
            }
        }
        println("exported " + nf + " functions, " + ns + " rtti symbols");
    }
}
