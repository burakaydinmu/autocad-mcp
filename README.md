# autocad-mcp

Açık olan AutoCAD'e yapay zeka uygulamasından (Claude Code, Claude Desktop, Codex …) gerçek, düzenlenebilir çizim nesneleri ekleyen yerel bir MCP sunucusu. Baretli Kafa YouTube kanalının 13. bölümünde kuruldu.

*A local MCP server that lets an AI assistant draw native, editable entities in a running AutoCAD (Windows, full AutoCAD, Node.js).*

- `server.mjs`: MCP sunucusu (stdio). Gelen isteği şemaya göre denetler. npm paketi yok.
- `bridge.ps1`: AutoCAD'le COM üzerinden konuşan PowerShell köprüsü.
- İnternete çıkmaz, port açmaz. Serbest komut / LISP çalıştırma aracı yok; 9 sabit araç var (çizim, katman, blok, okuma, yeni adla kaydetme).

## Kurulum (kısa)

1. Gereksinimler: Windows 10/11, tam sürüm AutoCAD (LT'de çalışmaz), Node.js LTS.
2. Klasörü boşluksuz bir yola koyun, örneğin `C:\autocad-mcp\`.
3. Claude Code: `claude mcp add --scope user autocad_local -- node C:\autocad-mcp\server.mjs`
4. AutoCAD'i açın, yapay zeka uygulamasını yeniden başlatın, «AutoCAD'e bağlı mısın?» diye sorun.

Claude Desktop ve Codex ayarları, araç listesi, güvenlik kuralları ve sık karşılaşılan hatalar: [OKU.md](OKU.md).

## Lisans

MIT ([LICENSE](LICENSE), Türkçe metin [LISANS.txt](LISANS.txt)). Yapay zekanın çizdiği her şey bir taslaktır; kontrol ve onay kullanıcıdadır.
