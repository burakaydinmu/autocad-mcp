# AutoCAD'e yapay zeka bağlantısı (yerel MCP sunucusu)

Baretli Kafa, Bölüm 13'te kurduğumuz bağlantının dosyaları. Yapay zeka uygulamanız (Claude, Codex …) bu sunucu üzerinden **bilgisayarınızda açık olan AutoCAD'e** gerçek, düzenlenebilir çizim nesneleri ekler.

- İki dosya: `server.mjs` (MCP sunucusu, gelen isteği denetler) ve `bridge.ps1` (AutoCAD'le konuşan köprü).
- İnternete çıkmaz, ağ portu açmaz, dosya göndermez. npm paketi yok.
- Serbest komut, LISP ya da kabuk komutu çalıştırma aracı yok; yalnız aşağıdaki 9 iş.

## Gereksinimler

| | |
|---|---|
| İşletim sistemi | Windows 10 / 11 (AutoCAD'in COM arayüzü yalnız Windows'ta) |
| AutoCAD | **Tam sürüm.** AutoCAD LT'de bu dışarıdan bağlanma (ActiveX / COM) yok, çalışmaz. |
| Node.js | LTS sürümü (nodejs.org) |
| PowerShell | Windows PowerShell 5.1 (Windows'la gelir) |
| Yapay zeka uygulaması | Yerel (stdio) MCP sunucusu çalıştırabilen bir uygulama: Claude Code, Claude Desktop, Codex … |

## Kurulum

1. Bu klasörü kısa, boşluksuz bir yola koyun, örneğin `C:\autocad-mcp\`. İçinde `server.mjs`, `bridge.ps1` ve `drawings\` olmalı.
2. Yapay zeka uygulamanıza tanıtın (birini seçin):
   - **Claude Code:** `claude mcp add --scope user autocad_local -- node C:\autocad-mcp\server.mjs` (`--scope user`: hangi klasörde açarsanız açın çalışır)
   - **Claude Desktop:** Ayarlar → Developer → Edit Config; `claude_desktop_config.json` içine:
     ```json
     { "mcpServers": { "autocad_local": { "command": "node", "args": ["C:\\autocad-mcp\\server.mjs"] } } }
     ```
   - **Codex:** `config.toml` içine:
     ```toml
     [mcp_servers.autocad_local]
     command = "node"
     args = ['C:\autocad-mcp\server.mjs']
     ```
3. AutoCAD'i açın. Yarım kalmış komut ya da açık pencere bırakmayın.
4. Yapay zeka uygulamasını kapatıp yeniden açın (araçlar ancak böyle yüklenir).
5. Deneyin: «AutoCAD'e bağlı mısın, hangi çizimler açık?»

## Araçlar

| Araç | İş |
|---|---|
| `status` | Bağlantı, açık çizimler, birim, nesne sayısı (yazmaz) |
| `new_drawing` | Yeni, milimetre birimli boş çizim. AutoCAD isteği "meşgul" diye reddedip çizimi yine de açarsa onu bulur; ikinci boş çizim açmaz. |
| `list_layers` | Katmanları oku (çizgi tipi ve kalınlığıyla) |
| `create_layer` | YENİ katman aç: çizgi tipi (DASHED, HIDDEN, CENTER, PHANTOM …; yoksa acadiso.lin'den yüklenir), renk, çizgi kalınlığı. Var olan katmana dokunmaz. |
| `list_entities` | Nesneleri, koordinatlarını, yazı stilini ve sınır kutusunu (bbox) oku; bir blok tanımının içini de okur (en çok 500) |
| `draw` | Çizgi, daire, dikdörtgen, 2B polyline, yazı, hizalı ölçü, blok yerleştirme, dolu daire, dolu 3–4 köşe; nesne başına çizgi tipi ölçeği; tek "geri al" grubu |
| `define_block` | Yeni blok tanımla (var olanın üstüne yazmaz) |
| `zoom_extents` | Çizimi ekrana sığdır |
| `save_as` | `drawings\` altına YENİ adla DWG kaydet |

## Yapamadıkları

Silme, taşıma, döndürme, yay, tarama (hatch; dolu alan için dolu daire ve dolu 3–4 köşe var), 3B katı, PDF'e çizdirme. Çizimin görüntüsünü almaz: kontrolü koordinatları geri okuyarak yapar, göz sizde. P&ID sembolleri düz çizgi, daire ve blok olarak çizilir (Plant 3D'nin akıllı nesneleri değil).

## Güvenlik

- Çizmeden önce etkin çizimin tam adını ister; arada başka çizime geçerseniz işlemi reddeder.
- Kilitli katmana yazmaz. Hata olursa o çağrıda eklediklerini geri siler.
- Yalnız `drawings\` klasörüne, yalnız yeni adla kaydeder; hiçbir dosyanın üstüne yazmaz.
- İş bilgisayarına kurmadan önce bilgi işleminize sorun. Kendi çizimleriniz açıkken deneme yapmayın; yeni çizim açtırın.

## Sık karşılaşılanlar

- **"AutoCAD is busy"**: AutoCAD'de açık bir komut ya da pencere var. Esc'e basıp yeniden deneyin.
- **"İşlem kullanılamıyor (MK_E_UNAVAILABLE)"**: AutoCAD açık değil ya da yapay zeka uygulamasıyla farklı yetkiyle (biri yönetici) çalışıyor.
- **Araçlar görünmüyor**: uygulamayı yeniden başlatın; yoldaki klasör adını kontrol edin. Klasörü taşırsanız 2. adımı yeni yolla tekrarlayın.
- **Türkçe harfler "?" çıkıyor**: AutoCAD'in varsayılan yazı stili (txt.shx) Türkçe harf içermiyor. Bu sürüm yazıları kendiliğinden UNICODE-ARIAL stiline (Arial) koyar; çizimin öbür yazılarına dokunmaz.
- **Zaman aşımı (90 sn)**: çok büyük çizimlerde her şeyi birden okutmayın, katman katman okutun. Zaman aşımından sonra körlemesine tekrar ettirmeyin, önce nesneleri okutun (iki kez çizilmesin).

## İpucu

Yapay zekanın tekrar eden bir hatası varsa ondan bir `HATALAR.md` dosyasına yazmasını isteyin (ne oldu, neden oldu, nasıl önlenecek) ve sonraki çizimde o listeye bakmasını söyleyin.

## Kaldırma

Claude Code: `claude mcp remove autocad_local` · Codex: `codex mcp remove autocad_local` · Claude Desktop: yapılandırma dosyasından satırı silin. Sonra klasörü silebilirsiniz.

## Sorumluluk

Yapay zekanın çizdiği her şey bir taslaktır. Ölçüleri, standart uygunluğunu ve imalata uygunluğu bir mühendis kontrol eder. Kodu kendi sorumluluğunuzda kullanın (bkz. `LISANS.txt`).
