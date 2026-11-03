// The first edition of the tolls, tunnels and paid parking catalog, served at
// /api/tolls until the admin panel saves its own (lib/tolls.js). Only what an
// official source publishes: the operator or the owner of the road or the
// parking (Vegagerðin, Spölur, Vaðlaheiðargöng, the national parks, the
// Nature Conservation Agency, Skatturinn, the City of Reykjavík). No guides of
// car rentals or aggregators. Where the source gives no price, none is shown.
//
// Checked by hand on 2026-11-03. Places left out because no official price
// was found that day: Skógafoss, Seljalandsfoss, Reynisfjara, Kerið, Geysir,
// Gullfoss, Hraunfossar, Stuðlagil.

const VERIFIED = "2026-11-03";

export const TOLLS_SEED = [
  {
    id: "vadlaheidargong",
    type: "toll_tunnel",
    name: "Vaðlaheiðargöng",
    lat: 65.7111, lon: -17.9859,
    // The two portals (OpenStreetMap): passing both within half an hour is a trip through.
    points: [[65.69384, -18.05367], [65.72838, -17.91803]],
    path: [[65.69384, -18.05367], [65.7111, -17.9859], [65.72838, -17.91803]],
    radius_m: 900,
    prices: [
      { class: "under_3_5t", isk: 2216, unit: "trip" },
      { class: "t3_5_7_5", isk: 3087, unit: "trip" },
      { class: "over_7_5t", isk: 6505, unit: "trip" },
    ],
    pay_url: "https://www.veggjald.is/en-gb",
    pay_methods: ["online", "account"],
    window_before_h: 24,
    window_after_h: 24,
    texts: {
      it: {
        summary: "Tunnel a pedaggio di 7,5 km sulla Ring Road vicino ad Akureyri. Nessun casello: le telecamere leggono la targa.",
        payment: "Paga la singola corsa su veggjald.is / tunnel.is con la targa, oppure con un account veggjald.is che addebita la carta dopo ogni passaggio. Rimorchi, roulotte e carrelli non pagano in più; i camper pagano in base al peso registrato.",
        window: "Da 24 ore prima a 24 ore dopo il passaggio.",
        penalty: "Dopo 24 ore il pedaggio va in addebito all'intestatario del veicolo (nessun costo in più); se non è pagato alla scadenza passa al recupero crediti (Inkasso) con una spesa aggiuntiva.",
        rental: "Auto a noleggio: se non paghi entro 24 ore il noleggiatore viene avvisato e addebita sulla tua carta il pedaggio più la sua commissione. Dopo 24 ore non si può più comprare la corsa singola.",
        alternative: "Senza pedaggio: la vecchia strada sul passo Víkurskarð, circa 16 km più lunga. Con maltempo è pericolosa: controlla umferdin.is. Il pedaggio si paga anche quando Víkurskarð è chiuso.",
      },
      en: {
        summary: "7.5 km toll tunnel on the Ring Road near Akureyri. No booths: cameras read the number plate.",
        payment: "Pay the single trip at veggjald.is / tunnel.is with the plate number, or with a veggjald.is account that charges your card after each trip. No extra charge for trailers, caravans or tent trailers; motorhomes pay by their registered weight.",
        window: "From 24 hours before to 24 hours after driving through.",
        penalty: "After 24 hours the toll is billed to the vehicle owner's online bank (no extra cost); if unpaid by the due date it goes to debt collection (Inkasso) with a fee.",
        rental: "Rental cars: if you don't pay within 24 hours the rental company is notified and charges your card the toll plus its service fee. After 24 hours the single trip can no longer be bought.",
        alternative: "Toll-free: the old road over the Víkurskarð pass, about 16 km longer. Hazardous in bad weather: check umferdin.is. The toll applies even when Víkurskarð is closed.",
      },
    },
    source_name: "Vaðlaheiðargöng (veggjald.is / tunnel.is)",
    source_url: "https://www.veggjald.is/en-gb/verd-greidsluleidir",
    sources: [
      { name: "Prices and payment methods", url: "https://www.veggjald.is/en-gb/verd-greidsluleidir" },
      { name: "Rental cars", url: "https://www.veggjald.is/en-gb/rental-cars" },
      { name: "Spurt & svarað", url: "https://www.veggjald.is/spurt--svarad" },
    ],
    verified_at: VERIFIED,
  },
  {
    id: "hornafjordur",
    type: "toll_road",
    name: "Hringvegur um Hornafjörð",
    lat: 64.2925, lon: -15.3,
    // The tolled section of Route 1 (OpenStreetMap, toll=yes); cameras at its ends.
    points: [[64.29122, -15.38899], [64.2782, -15.19866]],
    path: [[64.29122, -15.38899], [64.29286, -15.37846], [64.29365, -15.36775], [64.29373, -15.35516], [64.29367, -15.34011],
      [64.29367, -15.32968], [64.29347, -15.31869], [64.29243, -15.30747], [64.28941, -15.292], [64.28748, -15.28054],
      [64.28647, -15.27027], [64.28526, -15.25962], [64.28331, -15.2488], [64.28093, -15.23884], [64.27901, -15.22903],
      [64.27759, -15.21774], [64.27732, -15.20696], [64.2782, -15.19866]],
    radius_m: 700,
    prices: [
      { class: "under_3_5t", isk: 1500, unit: "trip" },
      { class: "t3_5_7_5", isk: 2100, unit: "trip" },
      { class: "over_7_5t", isk: 4500, unit: "trip" },
    ],
    pay_url: "https://www.spolur.is/",
    pay_methods: ["online", "bank"],
    window_after_h: 24,
    since: "2026-09-01",
    texts: {
      it: {
        summary: "Nuovo tratto della Ring Road a Hornafjörður (aperto a giugno 2026), a pedaggio dal 1° settembre 2026. Riscossione automatica: telecamere alle estremità del tratto, gestore Spölur.",
        payment: "La singola corsa si paga online su spolur.is con la targa. Altrimenti il conto arriva ogni mese all'intestatario del veicolo, con gli sconti per più passaggi (veicoli fino a 3,5 t: 950 ISK a corsa da 2 a 5 corse nel mese, 750 ISK da 6 a 22, al massimo 18.750 ISK al mese). Pagando la corsa singola online lo sconto non vale.",
        window: "Entro 24 ore dal passaggio.",
        penalty: "Se non paghi la corsa, il conto va all'intestatario del veicolo nella sua banca online, una volta al mese.",
        rental: "Auto a noleggio: l'intestatario è il noleggiatore, quindi il conto va a lui. Chiedi al ritiro come te lo addebita, o paga tu la corsa su spolur.is entro 24 ore.",
      },
      en: {
        summary: "New section of the Ring Road at Hornafjörður (opened June 2026), tolled from 1 September 2026. Fully automatic: cameras at both ends of the section, collected by Spölur.",
        payment: "Pay a single trip online at spolur.is with the plate number. Otherwise the vehicle owner is billed monthly, with discounts for more trips (vehicles up to 3.5 t: 950 ISK per trip for 2–5 trips a month, 750 ISK for 6–22, at most 18,750 ISK a month). No discount when a single trip is paid online.",
        window: "Within 24 hours of driving through.",
        penalty: "If you don't pay the trip, the bill goes to the vehicle owner's online bank, once a month.",
        rental: "Rental cars: the owner is the rental company, so the bill goes to them. Ask at pick-up how they charge it, or pay the trip yourself at spolur.is within 24 hours.",
      },
    },
    source_name: "Vegagerðin · Spölur",
    source_url: "https://www.vegagerdin.is/en/about-us/operation/news/gjaldtaka-a-hringvegi-1-um-hornafjord-hefst-i-september",
    sources: [
      { name: "Vegagerðin: Hornafjörður Ring road tolls (31 Aug 2026)", url: "https://www.vegagerdin.is/en/about-us/operation/news/gjaldtaka-a-hringvegi-1-um-hornafjord-hefst-i-september" },
      { name: "Spölur: Veggjöld um Hornafjarðarfljót", url: "https://www.spolur.is/" },
    ],
    verified_at: VERIFIED,
  },
  {
    id: "hvalfjardargong",
    type: "info",
    name: "Hvalfjarðargöng",
    lat: 64.2974, lon: -21.8534,
    points: [[64.30967, -21.90394], [64.28247, -21.83925]],
    path: [[64.30967, -21.90394], [64.29739, -21.85339], [64.28247, -21.83925]],
    radius_m: 900,
    prices: [],
    texts: {
      it: {
        summary: "Tunnel sotto lo Hvalfjörður sulla Ring Road a nord di Reykjavík: è GRATUITO. Il pedaggio non si paga più da quando il tunnel è passato allo Stato (2018).",
      },
      en: {
        summary: "Tunnel under Hvalfjörður on the Ring Road north of Reykjavík: it is FREE. There has been no toll since the tunnel was handed over to the State (2018).",
      },
    },
    source_name: "Stjórnarráðið · Vegagerðin",
    source_url: "https://www.stjornarradid.is/gogn/rit-og-skyrslur/stakt-rit/2018/10/01/Hvalfjardargong-formlega-afhent-islenska-rikinu/",
    sources: [
      { name: "Stjórnarráðið: Hvalfjarðargöng formlega afhent íslenska ríkinu", url: "https://www.stjornarradid.is/gogn/rit-og-skyrslur/stakt-rit/2018/10/01/Hvalfjardargong-formlega-afhent-islenska-rikinu/" },
      { name: "Vegagerðin: Jarðgöng á áætlun (2023) – \"gjaldfrjáls\" dal 2019", url: "https://wp-beta.vegagerdin.is/wp-content/uploads/2023/09/jardgong-a-aaetlun.-mat-a-ardsemi-umferdaroryggi-tengingu-svaeda-og-byggdathroun-mai-2023.pdf" },
    ],
    verified_at: VERIFIED,
  },
  {
    id: "thingvellir",
    type: "paid_parking",
    name: "Þingvellir",
    lat: 64.2556, lon: -21.1297,
    radius_m: 2500,
    prices: [
      { class: "motorcycle", isk: 400, unit: "day" },
      { class: "car_5", isk: 1000, unit: "day" },
      { class: "car_6_9", isk: 1200, unit: "day" },
      { class: "bus_10_19", isk: 2200, unit: "day" },
      { class: "bus_20_32", isk: 3800, unit: "day" },
      { class: "bus_33", isk: 4200, unit: "day" },
    ],
    pay_url: "https://www.thingvellir.is/thjonusta/bilastaedi-a-thingvoellum/greida-bilastaedi/",
    pay_methods: ["online"],
    texts: {
      it: {
        summary: "Parcheggi a pagamento del Parco nazionale di Þingvellir: la tariffa copre la gestione e i servizi dei parcheggi.",
        payment: "Si paga dalla pagina \"Greiða bílastæði\" del sito del parco. Altri modi di pagamento: verifica sul posto.",
      },
      en: {
        summary: "Paid parking in Þingvellir National Park: the fee covers running and servicing the car parks.",
        payment: "Pay from the \"Greiða bílastæði\" page of the park's website. Other ways to pay: check on site.",
      },
    },
    source_name: "Þjóðgarðurinn á Þingvöllum",
    source_url: "https://www.thingvellir.is/en/service/parking-service/",
    verified_at: VERIFIED,
  },
  {
    id: "skaftafell",
    type: "paid_parking",
    name: "Skaftafell",
    lat: 64.0167, lon: -16.9663,
    radius_m: 1200,
    prices: [
      { class: "motorcycle", isk: 450, unit: "day" },
      { class: "car_5", isk: 1110, unit: "day" },
      { class: "car_6_9", isk: 1440, unit: "day" },
      { class: "bus_10_21", isk: 2770, unit: "day" },
      { class: "bus_22_32", isk: 5200, unit: "day" },
      { class: "bus_33", isk: 9400, unit: "day" },
    ],
    pay_url: "https://www.vatnajokulsthjodgardur.is/en/payment-of-camping-and-regional-fees",
    pay_methods: ["app", "machine"],
    app_name: "Parka",
    texts: {
      it: {
        summary: "Tariffa d'area del Parco nazionale del Vatnajökull, riscossa al parcheggio: una telecamera legge la targa all'ingresso.",
        payment: "Con l'app Parka (servizio ufficiale del parco) o alle macchinette nel parcheggio.",
        window: "Vale fino a mezzanotte del giorno in cui paghi: puoi entrare e uscire liberamente. Metà prezzo se lo stesso giorno hai già pagato un'altra area a pagamento del parco (Jökulsárlón).",
      },
      en: {
        summary: "Vatnajökull National Park area fee, collected at the car park: a camera reads the plate on entry.",
        payment: "With the Parka app (the park's official service) or at the payment machines in the car park.",
        window: "Valid until midnight of the day you pay: drive in and out freely. Half price if you already paid another fee area of the park the same day (Jökulsárlón).",
      },
    },
    source_name: "Vatnajökulsþjóðgarður",
    source_url: "https://www.vatnajokulsthjodgardur.is/en/pricelist",
    sources: [
      { name: "Price list", url: "https://www.vatnajokulsthjodgardur.is/en/pricelist" },
      { name: "Payment of camping and regional fees", url: "https://www.vatnajokulsthjodgardur.is/en/payment-of-camping-and-regional-fees" },
    ],
    verified_at: VERIFIED,
  },
  {
    id: "jokulsarlon",
    type: "paid_parking",
    name: "Jökulsárlón",
    lat: 64.0484, lon: -16.1794,
    radius_m: 1500,
    prices: [
      { class: "motorcycle", isk: 450, unit: "day" },
      { class: "car_5", isk: 1110, unit: "day" },
      { class: "car_6_9", isk: 1440, unit: "day" },
      { class: "bus_10_21", isk: 2770, unit: "day" },
      { class: "bus_22_32", isk: 5200, unit: "day" },
      { class: "bus_33", isk: 9400, unit: "day" },
    ],
    pay_url: "https://www.vatnajokulsthjodgardur.is/en/payment-of-camping-and-regional-fees",
    pay_methods: ["app", "machine"],
    app_name: "Parka",
    texts: {
      it: {
        summary: "Tariffa d'area del Parco nazionale del Vatnajökull, riscossa al parcheggio della laguna: una telecamera legge la targa all'ingresso.",
        payment: "Con l'app Parka (servizio ufficiale del parco) o alle macchinette nel parcheggio.",
        window: "Vale fino a mezzanotte del giorno in cui paghi: puoi entrare e uscire liberamente. Metà prezzo se lo stesso giorno hai già pagato un'altra area a pagamento del parco (Skaftafell).",
      },
      en: {
        summary: "Vatnajökull National Park area fee, collected at the lagoon car park: a camera reads the plate on entry.",
        payment: "With the Parka app (the park's official service) or at the payment machines in the car park.",
        window: "Valid until midnight of the day you pay: drive in and out freely. Half price if you already paid another fee area of the park the same day (Skaftafell).",
      },
    },
    source_name: "Vatnajökulsþjóðgarður",
    source_url: "https://www.vatnajokulsthjodgardur.is/en/pricelist",
    sources: [
      { name: "Price list", url: "https://www.vatnajokulsthjodgardur.is/en/pricelist" },
      { name: "Payment of camping and regional fees", url: "https://www.vatnajokulsthjodgardur.is/en/payment-of-camping-and-regional-fees" },
    ],
    verified_at: VERIFIED,
  },
  {
    id: "landmannalaugar",
    type: "paid_parking",
    name: "Landmannalaugar",
    lat: 63.9905, lon: -19.0605,
    radius_m: 1500,
    prices: [
      { class: "motorcycle", isk: 750, unit: "day" },
      { class: "car_5", isk: 1500, unit: "day" },
      { class: "car_6_9", isk: 2450, unit: "day" },
      { class: "bus_10_21", isk: 5500, unit: "day" },
      { class: "bus_22_32", isk: 9500, unit: "day" },
      { class: "bus_33", isk: 16500, unit: "day" },
    ],
    texts: {
      it: {
        summary: "Parcheggio a pagamento dell'area protetta, gestito dall'Agenzia per la conservazione della natura (Náttúruverndarstofnun).",
        payment: "Come pagare: verifica sul posto.",
        window: "La tariffa vale al massimo per la giornata (00–24) in cui parcheggi.",
      },
      en: {
        summary: "Paid parking of the protected area, run by the Nature Conservation Agency (Náttúruverndarstofnun).",
        payment: "How to pay: check on site.",
        window: "The fee is valid at most for the day (00–24) you park.",
      },
    },
    source_name: "Stjórnartíðindi B 290/2026 (Náttúruverndarstofnun)",
    source_url: "https://adverts.stjornartidindi.is/B_nr_290_2026.pdf",
    verified_at: VERIFIED,
  },
  {
    id: "dyrholaey",
    type: "paid_parking",
    name: "Dyrhólaey",
    lat: 63.4041, lon: -19.1172,
    radius_m: 1500,
    prices: [
      { class: "motorcycle", isk: 300, unit: "day" },
      { class: "car_5", isk: 750, unit: "day" },
      { class: "car_6_9", isk: 1000, unit: "day" },
      { class: "bus_10_21", isk: 2000, unit: "day" },
      { class: "bus_22_32", isk: 4000, unit: "day" },
      { class: "bus_33", isk: 7500, unit: "day" },
    ],
    texts: {
      it: {
        summary: "Parcheggio a pagamento della riserva naturale, gestito dall'Agenzia per la conservazione della natura (Náttúruverndarstofnun).",
        payment: "Come pagare: verifica sul posto.",
        window: "La tariffa vale al massimo per la giornata (00–24) in cui parcheggi.",
      },
      en: {
        summary: "Paid parking of the nature reserve, run by the Nature Conservation Agency (Náttúruverndarstofnun).",
        payment: "How to pay: check on site.",
        window: "The fee is valid at most for the day (00–24) you park.",
      },
    },
    source_name: "Stjórnartíðindi B 290/2026 (Náttúruverndarstofnun)",
    source_url: "https://adverts.stjornartidindi.is/B_nr_290_2026.pdf",
    verified_at: VERIFIED,
  },
  {
    id: "reykjavik",
    type: "paid_parking",
    name: "Reykjavík · zone P1–P4",
    lat: 64.1466, lon: -21.9364,
    radius_m: 1200,
    prices: [],
    pay_url: "https://bilastaedasjodur.reykjavik.is/#/pay-for-parking",
    pay_methods: ["machine", "app", "online"],
    texts: {
      it: {
        summary: "In centro a Reykjavík si paga la sosta in 4 zone tariffarie (P1, P2, P3, P4), con prezzi e orari diversi: guarda il cartello della zona.",
        payment: "Al parchimetro con monete, carta o telefono, con un'app di pagamento della sosta, oppure online sul sito della città.",
      },
      en: {
        summary: "In central Reykjavík street parking is paid in 4 tariff zones (P1, P2, P3, P4), with different prices and hours: check the zone sign.",
        payment: "At the parking meter with coins, card or phone, with a parking payment app, or online on the city's website.",
      },
    },
    source_name: "Reykjavíkurborg",
    source_url: "https://reykjavik.is/en/parking/parking-spots",
    verified_at: VERIFIED,
  },
  {
    id: "kilometragjald",
    type: "info",
    name: "Kílómetragjald 2026",
    prices: [
      { class: "under_3_5t", isk: 6.95, unit: "km" },
    ],
    texts: {
      it: {
        summary: "Dal 1° gennaio 2026 tutti i veicoli pagano una tassa per chilometro percorso: 6,95 ISK/km per auto e fuoristrada fino a 3,5 t, di più per i veicoli più pesanti.",
        payment: "La paga l'intestatario del veicolo, che registra i chilometri.",
        rental: "Auto a noleggio: l'intestatario è il noleggiatore, registrato per pagarla a giornata o a chilometro. Chiedi al ritiro se e come te la addebita.",
      },
      en: {
        summary: "Since 1 January 2026 every vehicle pays a charge per kilometre driven: 6.95 ISK/km for cars and jeeps up to 3.5 t, more for heavier vehicles.",
        payment: "Paid by the registered owner of the vehicle, who reports the odometer.",
        rental: "Rental cars: the owner is the rental company, registered to pay it per day or per kilometre. Ask at pick-up whether and how they pass it on to you.",
      },
    },
    source_name: "Skatturinn · Ísland.is",
    source_url: "https://island.is/kilometragjald/gjald-fyrir-bifreidar-undir-10-tonn",
    sources: [
      { name: "Ísland.is: Gjald fyrir bifreiðar (undir 10 tonn)", url: "https://island.is/kilometragjald/gjald-fyrir-bifreidar-undir-10-tonn" },
      { name: "Skatturinn: Kílómetragjald", url: "https://www.skatturinn.is/einstaklingar/skattar-og-gjold/kilometragjald/" },
    ],
    verified_at: VERIFIED,
  },
];
