#include "engine_types.h"

#include "log.h"

#include <fstream>
#include <memory>
#include <sstream>

namespace iex {

TypeRegistry engineTypes;

std::uint32_t FieldKind::Size() const
{
    switch (kind) {
    case Kind::I8: case Kind::U8: case Kind::Bool: return 1;
    case Kind::I16: case Kind::U16: return 2;
    case Kind::I32: case Kind::U32: case Kind::F32: return 4;
    case Kind::I64: case Kind::U64: case Kind::F64: return 8;
    case Kind::ResRef: return 8;
    case Kind::CString: case Kind::CharPtr: case Kind::Ptr: return 8;
    case Kind::Chars: return count;
    case Kind::Struct: return type ? type->size : 0;
    case Kind::List: {
        // An embedded CTypedPtrList is a CPtrList whatever its element type.
        const TypeDesc* list = engineTypes.Get("CPtrList");
        return list ? list->size : 0;
    }
    case Kind::Array: return element ? element->Size() * count : 0;
    }
    return 0;
}

const FieldDesc* TypeDesc::Find(const std::string& field, std::uint32_t& offset) const
{
    auto it = fields.find(field);
    if (it != fields.end()) {
        offset = it->second.offset;
        return &it->second;
    }
    for (const auto& [base, baseOffset] : bases) {
        std::uint32_t inner = 0;
        if (const FieldDesc* f = base->Find(field, inner)) {
            offset = baseOffset + inner;
            return f;
        }
    }
    return nullptr;
}

TypeDesc* TypeRegistry::GetOrAdd(const std::string& name)
{
    auto it = types_.find(name);
    if (it != types_.end())
        return it->second;
    typeStore_.push_back(std::make_unique<TypeDesc>());
    TypeDesc* t = typeStore_.back().get();
    t->name = name;
    types_[name] = t;
    return t;
}

const TypeDesc* TypeRegistry::Get(const std::string& name) const
{
    auto it = types_.find(name);
    return it == types_.end() ? nullptr : it->second;
}

const FieldKind* TypeRegistry::ParseKind(const std::string& text)
{
    static const std::pair<const char*, Kind> prims[] = {
        {"i8", Kind::I8}, {"u8", Kind::U8}, {"i16", Kind::I16}, {"u16", Kind::U16}, {"i32", Kind::I32},
        {"u32", Kind::U32}, {"i64", Kind::I64}, {"u64", Kind::U64}, {"f32", Kind::F32}, {"f64", Kind::F64},
        {"bool", Kind::Bool}, {"resref", Kind::ResRef}, {"cstring", Kind::CString}, {"charptr", Kind::CharPtr},
    };
    auto k = std::make_unique<FieldKind>();
    bool ok = false;
    for (const auto& [name, kind] : prims) {
        if (text == name) {
            k->kind = kind;
            ok = true;
        }
    }
    if (!ok) {
        const auto colon = text.find(':');
        const std::string head = text.substr(0, colon);
        const std::string rest = colon == std::string::npos ? "" : text.substr(colon + 1);
        if (head == "chars") {
            k->kind = Kind::Chars;
            k->count = static_cast<std::uint32_t>(std::stoul(rest));
            ok = true;
        } else if (head == "list" && (rest == "int" || rest == "void")) {
            // List of integers stored in the node data (object ids), or of untyped pointers.
            k->kind = Kind::List;
            k->count = rest == "int" ? 1 : 0;
            ok = true;
        } else if (head == "struct" || head == "ptr" || head == "list") {
            k->kind = head == "struct" ? Kind::Struct : head == "ptr" ? Kind::Ptr : Kind::List;
            k->type = rest == "void" ? nullptr : GetOrAdd(rest);
            ok = true;
        } else if (head == "array") {
            const auto colon2 = rest.find(':');
            k->kind = Kind::Array;
            k->count = static_cast<std::uint32_t>(std::stoul(rest.substr(0, colon2)));
            k->element = ParseKind(rest.substr(colon2 + 1));
            ok = k->element != nullptr;
        }
    }
    if (!ok)
        return nullptr;
    kindStore_.push_back(std::move(k));
    return kindStore_.back().get();
}

const TypeDesc* TypeRegistry::TypedNode(const TypeDesc* element)
{
    if (!element)
        return nullptr;
    const std::string name = "CPtrList::CNode<" + element->name + ">";
    if (const TypeDesc* existing = Get(name))
        return existing;
    const TypeDesc* node = Get("CPtrList::CNode");
    if (!node)
        return nullptr;
    TypeDesc* t = GetOrAdd(name);
    t->size = node->size;
    for (const auto& [fieldName, field] : node->fields) {
        FieldDesc copy = field;
        if (fieldName == "pNext" || fieldName == "pPrev")
            copy.kind = ParseKind("ptr:" + name);
        else if (fieldName == "data")
            copy.kind = ParseKind("ptr:" + element->name);
        t->fields[fieldName] = copy;
    }
    return t;
}

bool TypeRegistry::Load(const std::string& path)
{
    std::ifstream in(path);
    if (!in) {
        Log("Engine description not found: %s", path.c_str());
        return false;
    }
    TypeDesc* current = nullptr;
    std::string line;
    int lineNo = 0;
    while (std::getline(in, line)) {
        ++lineNo;
        if (line.empty() || line[0] == '#')
            continue;
        std::istringstream ss(line);
        std::string record;
        ss >> record;
        if (record == "type") {
            std::string name, size, base;
            ss >> name >> size;
            current = GetOrAdd(name);
            current->size = static_cast<std::uint32_t>(std::stoul(size, nullptr, 16));
            while (ss >> base) {
                if (base.rfind("elem=", 0) == 0) {
                    current->element = GetOrAdd(base.substr(5));
                    continue;
                }
                // base=<Name>@<offset>
                const auto eq = base.find('='), at = base.find('@');
                if (eq == std::string::npos || at == std::string::npos)
                    continue;
                current->bases.emplace_back(GetOrAdd(base.substr(eq + 1, at - eq - 1)),
                                            static_cast<std::uint32_t>(std::stoul(base.substr(at + 1), nullptr, 16)));
            }
        } else if (record == "symbol") {
            std::string name, rva;
            ss >> name >> rva;
            symbols_[name] = static_cast<std::uint32_t>(std::stoul(rva, nullptr, 16));
        } else if (record == "const") {
            std::string name, value;
            ss >> name >> value;
            consts_[name] = std::stoull(value, nullptr, 16);
        } else if (record == "callsite") {
            std::string rva, target;
            ss >> rva >> target;
            callSites_.push_back(CallSite{static_cast<std::uint32_t>(std::stoul(rva, nullptr, 16)), target});
        } else if (record == "method") {
            // method <Class> <luaName> fn:<rva>|vt:<offset> <ret> [arg...]
            MethodDesc m;
            std::string target, arg;
            ss >> m.className >> m.luaName >> target >> m.ret;
            while (ss >> arg)
                m.args.push_back(arg);
            if (target.size() < 4 || (target.rfind("fn:", 0) != 0 && target.rfind("vt:", 0) != 0) || m.ret.empty()) {
                Log("%s:%d: bad method record", path.c_str(), lineNo);
                continue;
            }
            m.isVirtual = target[0] == 'v';
            m.target = static_cast<std::uint32_t>(std::stoul(target.substr(3), nullptr, 16));
            methods_.push_back(std::move(m));
        } else if (record == "field" && current) {
            std::string name, offset, kind;
            ss >> name >> offset >> kind;
            const FieldKind* k = ParseKind(kind);
            if (!k) {
                Log("%s:%d: unknown field kind '%s'", path.c_str(), lineNo, kind.c_str());
                continue;
            }
            current->fields[name] = FieldDesc{name, static_cast<std::uint32_t>(std::stoul(offset, nullptr, 16)), k};
        }
    }
    Log("Engine description loaded: %zu types, %zu symbols, %zu call sites, %zu methods", types_.size(),
        symbols_.size(), callSites_.size(), methods_.size());
    return true;
}

std::uint32_t TypeRegistry::Symbol(const std::string& mangled) const
{
    auto it = symbols_.find(mangled);
    return it == symbols_.end() ? 0 : it->second;
}

std::uint32_t TypeRegistry::SymbolByQualifiedName(const std::string& qualified) const
{
    // A::B::C -> _ZN1A1B1CE... (or _ZNK... for const members)
    std::string nested;
    std::size_t pos = 0;
    int parts = 0;
    while (pos <= qualified.size()) {
        std::size_t next = qualified.find("::", pos);
        const std::string part = qualified.substr(pos, next == std::string::npos ? std::string::npos : next - pos);
        if (part.empty())
            return 0;
        nested += std::to_string(part.size()) + part;
        ++parts;
        if (next == std::string::npos)
            break;
        pos = next + 2;
    }
    if (parts < 2)
        return 0;
    std::uint32_t found = 0;
    for (const char* head : {"_ZN", "_ZNK"}) {
        const std::string prefix = std::string(head) + nested + "E";
        for (const auto& [name, rva] : symbols_) {
            if (name.compare(0, prefix.size(), prefix) == 0) {
                if (found && found != rva)
                    return 0;
                found = rva;
            }
        }
    }
    return found;
}

bool TypeRegistry::Const(const std::string& name, std::uint64_t& value) const
{
    auto it = consts_.find(name);
    if (it == consts_.end())
        return false;
    value = it->second;
    return true;
}

std::vector<std::uint32_t> TypeRegistry::CallSitesOf(const std::string& target) const
{
    std::vector<std::uint32_t> sites;
    for (const CallSite& c : callSites_) {
        if (c.target == target)
            sites.push_back(c.rva);
    }
    return sites;
}

std::unordered_map<std::string, std::string> ReadBuildRecord(const std::string& path)
{
    std::unordered_map<std::string, std::string> values;
    std::ifstream in(path);
    std::string line;
    while (std::getline(in, line)) {
        if (line.rfind("build ", 0) != 0)
            continue;
        std::istringstream ss(line.substr(6));
        std::string pair;
        while (ss >> pair) {
            const auto eq = pair.find('=');
            if (eq != std::string::npos)
                values[pair.substr(0, eq)] = pair.substr(eq + 1);
        }
        break;
    }
    return values;
}

} // namespace iex
