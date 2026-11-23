// =====================================================================
// Sentetik veri için Türkçe ad ve soyad listeleri (scripts/sentetik_veri.mjs kullanır)
//
// Adlar doğum kuşağına göre seçilir: 1970 doğumlu birinin adı ile 2002 doğumlu
// birinin adı farklı dönemlerin modasını yansıtır. Her listede sık olan başta yazılır.
// Soyadlar: sık soyadları (başta en sık) + uzun kuyruk (Ege yöresi, "-oğlu" ekli,
// birleşik soyadları). Gerçek kişiler değildir; ad ve soyad rastgele eşleştirilir.
// =====================================================================

// ---- Erkek adları ----------------------------------------------------
// Her kuşakta yaygın
export const ERKEK_GENEL = ["Mehmet", "Mustafa", "Ahmet", "Ali", "Hüseyin", "Hasan", "İbrahim", "Murat",
  "İsmail", "Osman", "Yusuf", "Ömer", "Ramazan", "Halil", "Süleyman", "Abdullah", "Mahmut", "Recep", "Fatih",
  "Kadir", "Emre", "Salih", "Hakan", "Adem", "Kemal", "Bayram", "Orhan", "Metin", "Uğur", "Yasin", "Musa",
  "Yunus", "Harun", "Hamza", "Selim", "Kenan", "Cemal", "Serdar", "Erkan", "Kaan", "Can", "Bilal", "Mesut",
  "Zeki", "Veysel", "Cuma", "Nurullah", "Abdulkadir", "İsa", "Eyüp", "Sami", "Tarık"];
// 1955–1979 doğumlular
export const ERKEK_ESKI = ["Hüsnü", "Nevzat", "Necati", "Şükrü", "Rıza", "Kazım", "Hilmi", "Sabri", "Nuri",
  "Fikret", "Cevdet", "Ziya", "Nazım", "Rahmi", "Remzi", "Bekir", "Sadık", "Veli", "Hayri", "Lütfi", "Tahsin",
  "İrfan", "Kamil", "Şevket", "Muzaffer", "Rasim", "Yılmaz", "Ünal", "Turgut", "Bülent", "Erol", "Ayhan",
  "Erdal", "Ercan", "Cengiz", "Levent", "Tuncay", "Zafer", "Nihat", "Sedat", "Taner", "Turgay", "İlhan",
  "Doğan", "Haluk", "Yalçın", "Nusret", "Selahattin", "Nurettin", "Bahattin", "Alaattin", "Şaban", "Durmuş",
  "Dursun", "Hikmet", "Kemalettin", "Cafer", "Hidayet", "Mithat", "Necdet", "Oktay", "Rüstem", "Sefer",
  "Talat", "Yaşar", "Zekeriya", "Abdurrahman", "Mehmet Emin", "Hacı", "Kerim", "Mükremin", "Şahin", "Halis"];
// 1980–1994 doğumlular
export const ERKEK_ORTA = ["Serkan", "Burak", "Volkan", "Sinan", "Gökhan", "Onur", "Özgür", "Ufuk", "Alper",
  "Selçuk", "Tamer", "Cihan", "Erhan", "Ferhat", "Sercan", "Gürkan", "Tolga", "Barış", "Cem", "Okan", "Koray",
  "Tayfun", "Engin", "Erdem", "Ozan", "Orçun", "Utku", "Caner", "Cenk", "Emrah", "Ersin", "Evren", "Fırat",
  "Gökay", "İlker", "Kerem", "Kürşat", "Mert", "Oğuz", "Oğuzhan", "Önder", "Özkan", "Serhat", "Soner",
  "Tuğrul", "Umut", "Ümit", "Yavuz", "Yiğit", "Anıl", "Arda", "Deniz", "Gökmen", "Hüseyin Can", "Ercüment",
  "Bora", "Cüneyt", "Erdinç", "Eray", "Erman", "Gürhan", "Hakkı", "İlkay", "Levent", "Mutlu", "Nail",
  "Olcay", "Ömür", "Recai", "Savaş", "Sezgin", "Şenol", "Taylan", "Tunç", "Turan", "Şehmus", "Mazlum"];
// 1995–2007 doğumlular
export const ERKEK_YENI = ["Muhammet", "Furkan", "Enes", "Batuhan", "Berkay", "Mücahit", "Taha", "Emir",
  "Eren", "Efe", "Alperen", "Berk", "Doğukan", "Emirhan", "Ege", "Baran", "Çağan", "Çağrı", "Ertuğrul",
  "Göktuğ", "Kutay", "Metehan", "Oğulcan", "Sefa", "Semih", "Tugay", "Tunahan", "Yağız", "Muhammed",
  "Samet", "Talha", "Ensar", "Arda", "Kerem", "Umut", "Yiğit", "Onur", "Mert", "Berkan", "Bünyamin",
  "Cihangir", "Egemen", "Erdi", "Erkam", "Görkem", "Hüseyin Emre", "İlhan", "Kağan", "Melih", "Mirza",
  "Oğuzhan", "Ramazan", "Sinan", "Tolga", "Ufuk", "Yasin", "Yusuf Ziya", "Zafer", "Abdulsamet", "Ahmet Faruk"];
// Çift adlar (yaklaşık %7)
export const ERKEK_CIFT = ["Mehmet Ali", "Ali Osman", "Ali Rıza", "Mehmet Emin", "Hasan Hüseyin", "Halil İbrahim",
  "Yunus Emre", "Mehmet Akif", "Muhammed Ali", "Ahmet Can", "Mustafa Kemal", "Ömer Faruk", "Ali İhsan",
  "Mehmet Salih", "İsmail Hakkı", "Mehmet Fatih", "Ahmet Kaan", "Muhammet Emin", "Hüseyin Avni", "Ali Kemal"];

// ---- Kadın adları ----------------------------------------------------
export const KADIN_GENEL = ["Fatma", "Ayşe", "Emine", "Hatice", "Zeynep", "Elif", "Meryem", "Zehra", "Esra",
  "Merve", "Özlem", "Sevgi", "Derya", "Gül", "Yasemin", "Hülya", "Dilek", "Melek", "Sultan", "Şerife",
  "Nur", "Aysun", "Gülsüm", "Hacer", "Ebru", "Esma", "Havva", "Rukiye", "Songül", "Asiye"];
export const KADIN_ESKI = ["Hanife", "Fadime", "Cemile", "Saniye", "Nurten", "Nermin", "Gülten", "Sevim", "Nuray",
  "Nurhan", "Aysel", "Aynur", "Leyla", "Nazmiye", "Şükran", "Müzeyyen", "Nebahat", "Perihan", "Kadriye",
  "Kevser", "Safiye", "Sabahat", "Ayten", "Türkan", "Gönül", "Filiz", "Serpil", "Nurcan", "Gülşen", "Sibel",
  "Arzu", "Hale", "Füsun", "Canan", "Sema", "Semra", "Birsen", "Zerrin", "Nilgün", "Ümran", "Saadet", "Gülay",
  "Nazan", "Necla", "Sevinç", "Tülin", "Yıldız", "Zübeyde", "Elmas", "Döndü", "Hamiyet", "Melahat", "Naciye"];
export const KADIN_ORTA = ["Tuğba", "Gamze", "Pınar", "Aslı", "Burcu", "Seda", "Didem", "Yeliz", "Esin",
  "Hande", "Şule", "Tuba", "Özge", "Ayşegül", "Gözde", "Gizem", "Duygu", "Sinem", "Ceren", "Aylin", "Banu",
  "Bahar", "Berna", "Çiğdem", "Deniz", "Eda", "Emel", "Funda", "Hilal", "İlknur", "Meltem", "Nihan", "Nil",
  "Oya", "Serap", "Sevda", "Tülay", "Yeşim", "Zuhal", "Nesrin", "Müge", "Nilay", "Pelin", "Ayşen", "Dilber",
  "Ebru", "Elvan", "Ferda", "Gülşah", "Hümeyra", "İpek", "Nagehan", "Neslihan", "Selda", "Sevil", "Şebnem"];
export const KADIN_YENI = ["Büşra", "Kübra", "Cansu", "Damla", "İrem", "Melis", "Ezgi", "Buse", "Begüm", "Ecem",
  "Ece", "Selin", "Dilara", "Beyza", "Rabia", "Sena", "Şeyma", "Sude", "Aleyna", "İlayda", "Melike", "Nisa",
  "Simge", "Yağmur", "Aybüke", "Betül", "Cemre", "Ilgın", "Kardelen", "Nazlı", "Kader", "Sevde", "Tuğçe",
  "Gizem", "Hilal", "Pelin", "Gamze", "Merve", "Elif", "Asena", "Aslıhan", "Berfin", "Ceylin", "Dilan",
  "Esila", "Gülizar", "Helin", "Irmak", "Melisa", "Özlem", "Rümeysa", "Sıla", "Tuana", "Zeren"];
export const KADIN_CIFT = ["Ayşe Nur", "Fatma Nur", "Elif Nur", "Hatice Kübra", "Zeynep Sude", "Emine Gül",
  "Fatma Zehra", "Esra Nur", "Kübra Nur", "Sena Nur", "Merve Nur", "Ayşe Gül", "Zehra Nur", "Hatice Nur",
  "Fatma Betül", "Elif Su", "Zeynep Nur", "Emine Nur", "Büşra Nur", "Ayşe Sena"];

// ---- Soyadları -------------------------------------------------------
// En sık soyadları (sıklık sırasına yakın; başta en sık)
export const SOYAD_SIK = ["Yılmaz", "Kaya", "Demir", "Çelik", "Şahin", "Yıldız", "Yıldırım", "Öztürk", "Aydın",
  "Özdemir", "Arslan", "Doğan", "Kılıç", "Aslan", "Çetin", "Kara", "Koç", "Kurt", "Özkan", "Şimşek", "Polat",
  "Özcan", "Korkmaz", "Çakır", "Erdoğan", "Yavuz", "Can", "Acar", "Şen", "Aktaş", "Güler", "Yalçın", "Güneş",
  "Bozkurt", "Bulut", "Keskin", "Ünal", "Turan", "Gül", "Özer", "Işık", "Kaplan", "Avcı", "Sarı", "Tekin",
  "Taş", "Köse", "Yüksel", "Ateş", "Aksoy", "Yiğit", "Uçar", "Tunç", "Erdem", "Sönmez", "Karaca", "Altun",
  "Kalkan", "Eren", "Akın"];
// Uzun kuyruk: daha seyrek soyadları (eşit ağırlıkla seçilir)
export const SOYAD_SEYREK = [
  // Genel
  "Toprak", "Güven", "Demirci", "Karakaya", "Bilgin", "Coşkun", "Duman", "Ekinci", "Oral", "Sezer", "Yücel",
  "Akbulut", "Erol", "Akgül", "Gündoğdu", "Uysal", "Kocabaş", "Ertürk", "Bayram", "Tuna", "Çiftçi",
  "Kahraman", "Kızılkaya", "Aydoğan", "Baysal", "Günay", "Önal", "Demirtaş", "Tokgöz", "Karadağ", "Akyol",
  "Oğuz", "Özbek", "Sevim", "Cengiz", "Türkmen", "Aydemir", "Durmaz", "Koçak", "Ercan", "Sağlam", "Uzun",
  "Altıntaş", "Bostancı", "Karabulut", "Kandemir", "Uslu", "Akdeniz", "Dinç", "Tosun", "Alkan", "Akçay",
  "Akdağ", "Akkaya", "Akpınar", "Aksu", "Albayrak", "Altınkaya", "Arıkan", "Aslantaş", "Atalay", "Ayaz",
  "Aydınlı", "Bakır", "Balcı", "Baş", "Başaran", "Batur", "Bayındır", "Bayrak", "Bektaş", "Benli", "Biçer",
  "Bingöl", "Bozdağ", "Budak", "Cebeci", "Ceylan", "Cömert", "Çakmak", "Çalışkan", "Çam", "Çevik", "Çiçek",
  "Çolak", "Daş", "Demirel", "Deniz", "Dikmen", "Dilek", "Doğru", "Dönmez", "Dursun", "Ekici", "Elmas",
  "Emre", "Erbaş", "Ergin", "Ergün", "Erkan", "Erkoç", "Ersoy", "Esen", "Eser", "Fidan", "Gedik", "Genç",
  "Gök", "Gökçe", "Gökmen", "Gönül", "Görür", "Gümüş", "Gündüz", "Gürbüz", "Gürel", "Güzel", "Hançer",
  "İnce", "İnan", "İpek", "Kaçar", "Kalaycı", "Kanat", "Karagöz", "Karahan", "Karakuş", "Karataş", "Kaynak",
  "Kazan", "Keleş", "Kemer", "Kır", "Kırmızı", "Kocaman", "Kolay", "Konak", "Koyuncu", "Kuru",
  "Kuş", "Kutlu", "Küçük", "Mutlu", "Metin", "Oktay", "Olgun", "Orhan", "Özbay", "Özen", "Özgür",
  "Özkaya", "Öztekin", "Özyurt", "Pehlivan", "Peker", "Saka", "Saraç", "Savaş", "Sayın", "Seçkin",
  "Selçuk", "Serin", "Sevinç", "Sezgin", "Soylu", "Sungur", "Şahan", "Şanlı", "Şener", "Şimşir", "Tan",
  "Taşdemir", "Taşkın", "Tatlı", "Tekeli", "Temel", "Teke", "Tezcan", "Topal", "Topçu", "Tuncer", "Turgut",
  "Tutar", "Uğur", "Ulusoy", "Uyar", "Üstün", "Varol", "Yaman", "Yanık", "Yaşar", "Yazıcı", "Yener",
  "Yeşil", "Yıldırımlı", "Yolcu", "Yurt", "Yurtsever", "Zengin", "Ağca", "Ateşoğlu", "Akar", "Çınar", "Er",
  "Erim", "Karakoç", "Oruç", "Sarıkaya", "Soydan", "Tural", "Yalın", "Bal", "Börü", "Bayar", "Boz", "Dağ",
  // Ege / İzmir yöresi
  "Yörük", "Ege", "Zeybek", "Efe", "Kocabıyık", "Ödemişli", "Tireli", "Bergamalı", "Manisalı", "Muğlalı",
  "Torbalı", "Bayındırlı", "Menemenli", "Kemalpaşalı", "Salihli", "Akhisarlı", "Kınıklı", "Uşaklı",
  "Çeşmeli", "Aydınoğlu", "Kozak", "Tepe", "Bozyaka", "Narlı", "Zeytin",
  "Üzümcü", "İncirci", "Tütüncü", "Pamuk", "Çakırca", "Sarıçam", "Urlalı", "Selçuklu",
  // -oğlu ekli
  "Karaoğlu", "Hacıoğlu", "Kocaoğlu", "Ahmetoğlu", "Osmanoğlu", "Mollaoğlu", "Ustaoğlu", "Bayraktaroğlu",
  "Kayaoğlu", "Demiroğlu", "Yazıcıoğlu", "Çelikoğlu", "Hasanoğlu", "Mustafaoğlu", "Alioğlu", "Şeyhoğlu",
  "Kahyaoğlu", "Ağaoğlu", "Beyoğlu", "Çavuşoğlu", "Dervişoğlu", "Hocaoğlu", "Kadıoğlu",
  "Karamanoğlu", "Kurtoğlu", "Oğuzoğlu", "Şahinoğlu", "Topaloğlu", "Uzunoğlu", "Yusufoğlu", "Ömeroğlu",
  "Bekiroğlu", "Halisoğlu", "Kasapoğlu", "Terzioğlu", "Demircioğlu", "Bakkaloğlu", "Kabakçıoğlu",
  // Birleşik soyadları
  "Akdemir", "Akyıldız", "Akkurt", "Akyüz", "Alpaslan", "Altıner", "Aytekin", "Bozdemir", "Demirkol",
  "Demiröz", "Erdemir", "Erkılıç", "Gökdemir", "Gökalp", "Gülbahar", "Güneyli", "Karabıyık", "Karadeniz",
  "Karakurt", "Kılıçarslan", "Kızıltaş", "Özdağ", "Özkök", "Öztaş", "Sarıgül", "Taşçı", "Tokmak", "Yeşilyurt",
  "Bozoğlan", "Karaaslan", "Akarsu", "Cankurt", "Erdoğdu", "Gündoğan", "Kocatürk",
  "Ertekin", "Ayvaz", "Bilgiç", "Duru", "Gürsoy", "Kalender", "Okur", "Sevindik", "Tekinalp",
];
