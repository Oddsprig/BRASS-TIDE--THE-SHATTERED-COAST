<!-- brass-tide-series:29:start -->
# v0.029 source verification

SOURCE CHECKS RECORDED: 70 native suites recorded from supplied logs. Feature acceptance requires lead review.

<!-- series-source-logs:29 -->
Native log evidence: all 70 registered suites have positive completion summaries and no fatal/error/fail/timeout marker.

| Suite | Actual completion summary | Log SHA256 | Fixture SHA256 |
| --- | --- | --- | --- |
| damage | damage: all native tests passed | b739e4617b4484c4acb0f47fbb293df1b2c19622353a96af5dbe6ec417dd04a2 | 77c560f0c171c19546e7adcbbfebd7e858742b4b4de4e5aa6833bf018e39e51e |
| battle | battle: all native tests passed | 0ffa9b311ac15d771dec7ccaf0f3e0ec8c14b744739e0560ed8a9d7ca6f67868 | bb96fb83ac8cd5ca8c5c5452ee99381b4ffd9ffc25d9bed4f719f84ac0ca822a |
| navigation | navigation: direct, island detour, blocked targets, barriers, diagonal corners, shore connections, bounded finite graph, 10 ports and 19 routes passed | 7338a6c9b6e6d5b1420d4077604e2215b8dad8ed774e3d52a1e38b53547e2417 | 32c705d8ca3d939de5b4eff56e08aa3f2d518db26e9be3226da8a144736b5073 |
| economy | ALL NATIVE ECONOMY TESTS PASSED (86831 checks in 2822 ms) | 81ad1fa59de2b6b33155299b9c400d6510241898806ab425597fff88c7321116 | fa046ca3fbd31e2dce6839e5d2f032fd98728596887b7bc0181268b8e4dd7fa4 |
| construction | CONSTRUCTION PASS: 2827 checks in 16 ms | 10572b3e5cf56afa43cd0df011d3fe5a72248c0dee1759039b5e5eb7936b09aa | 32710db151b22b5334dea87b93fe9a8338abcd48e4ae16e8a4758b653ae4fdd3 |
| fleet_economy | fleet cash: 1266 checks, 0 failures, 3993 ms | 1b936237017bd5151afe9066f6677a87b728ad6fe65ef23d8117dd9bc7ec5e27 | bbd6fbf30aa8ed6f84731e98f68ca6ec7b147abbeec1b953d8c718464be09b74 |
| campaign_cash | campaign cash: 458 checks, 0 failures, 9428 ms | c704921c602999bd07a3ca7682c74622ebbbb9a23ec94243aae2dab4f803e771 | f8d29c1aebca21c2617db823058ca9396ba88ee778f527ca2ccbfbe5cbc255ef |
| save_validation | save validation: 89 checks, 0 failures, 852ms | 7abff06d74ab6d6358ea93436e412aa3ee828cbc5286cba78c6d0cc2c7140f0d | c744d20002a4f0bca3205976a4ce85535c375172d97ee283c0a3ceaa943e84c6 |
| runtime | runtime: 124 checks, 0 failures, 2201ms; background/headless only | 6ce3bccf7477c7255ec0d7ca03fd3d3708846f83274ff5045fcba382fcd8afbf | f4d4b4b93800c5f2708ed4ebfc203848c68dc8f2c3890ca313f36c1920792bb1 |
| voyage | voyage: 68 checks, 0 failures, 9934ms; largest fleet14 | 19ae5f730ec5b263445a4a005ada3bfc2c20901ec1ef5127261f7bbbe7d32778 | d3551098db3afb91e7fe89333d1cafaee46151326cd7b569b7365ebc5a0ba65a |
| tactics | tactics: 114 checks, 0 failures | b4ac1ec02d3fbaef3501307aa261fd613275837d134c4f548ff21bcec7b129bf | d7db827e3b7df594c45098726df879d910f71036fc52caecb93150176ae5668e |
| refit | refit: 348 checks, 0 failures | 67e16229d263ea8019b4b31625fe6c6dd8290729ef00a5a3f376955bb1b99739 | feb41f0933a6dbae7e5d097b2ea7f4e466bc44510bb33eda583f33efecf6e1b0 |
| fleet_points | fleet points: 99 checks, 0 failures, 1998ms | 9ef11353eb8f8bade88cb38af9d8bc9bac604211f488c0ce0d6c6d4e5f08d42d | edd7b5e5f234c9fdc7788fe42e57e6dc9d63188f14d949bf30b982f98fbf7724 |
| commander | commander: 24 checks, 0 failures; background only | 76ba0b7f9377afbd36cbdefaa7ca93f99c7d9e1c1739aa9ae45ab4a33a77b55f | 2351704e996dfa4eeb4420dacd4d6b152d49bfed86ac139b7c2bc79231026cd9 |
| autovoyage | voyage: 68 checks, 0 failures, 9608ms; largest fleet13 | 94998de0ef7176b014239a8022116d31d6f3b01c94b5e1b409d16750c2a40f22 | 8a8b112e908ba17741b1c33930ec311f604364c4aec080b7b95712fb9d44ab4f |
| laboratory | LABORATORY: 81 checks, 0 failures | 3e04e8a5ddc72eea91bf8b7c958984603e28d17738da4e1eb7c9cc87abe245dd | aaf64e633b04a43409377a2372a80b7381422abbe3a250c9727bc2214da79ed1 |
| combat_events | combat_events: 10131 checks, 0 failures | 82fc26360bdce3336a603a3ab9829097a1f810ac90b113db66f59585ac7902b0 | 9f24a006ff8599d67f06feaf8286f892158b5a7a5ed76380fe1a9e927e47f682 |
| audio | AUDIO: 1233 checks, 0 failures; decoding/scheduling only, no audition | dc52ef60020901e63867ba8fcf753ac89998a82f7d4ff8e9e26b0b65af55e924 | a5bcdad0078b32042a6084429e105c7168716ea9be09b19bfad50675562d40a9 |
| map_revision | map revision: 361 checks, 0 failures, 3378ms | 2e63c1cee8587b10abf81caf1e6b46ccedf7348ba2f92b5e0b646395d12b00b9 | 2a1feb090ee384e1880c4f910cec3e8431f0b52a2bc0d0876d8336861746bde3 |
| mount_layout | mount_layout: 1483 checks, 0 failures | b2e4acb76b13ab4b5d0bb1d7cd9b0b26b34f5ce2612782aa49c477ddeb07fec3 | 81ce2511ea402eadd102ec5c75b0cbe64625e4d9590f54888026bb72cd6778ee |
| presentation | PRESENTATION: 611 checks, 0 failures | 03d72af6f25270b7c56ebef8063833419701d9bd04eb2863d76435002960ec3f | f23d3545118fa67c64be7ccad0f8b0adc2349b824476338e8478a16563678d00 |
| feedback | FEEDBACK: 3952 checks, 0 failures | c27dee7d8df2bb1709b4381e6b69dac22682a52503c5b48720da17f9edc2dca2 | 8cc5685baafa67d9967dc5c6c73960cc5f28961b8b95c29388358415a3a52f80 |
| expedition | expedition: 23 checks, 0 failures | 6fe22d26ea63a3208412d99f503f871348788eb078a6504ec27520c60f193219 | 1461e7d12a3e1de6bc6f7147423df8d172715bf246ccadda4dcb65a17262ecdd |
| campaign_logistics | campaign logistics: 16 checks, 0 failures | cfe30045d9ed376defa3cc9ab89fdae1cfb2596438f10bf5bc6c182753e89536 | 3c03b17f99dda5ab4dd83bb0d4239c126bc45f472625a9a44ccc1a17c4853a41 |
| exploration | exploration: 270 checks, 0 failures | 9ee1c9b805e027cb9170b19c97761ddce58720c3caca9b0e701cd77997300dec | cc5a177e4832b769dc9c1da07d2f3570c108d789c5e006975dc9da163c213766 |
| island_voyage | island voyage: 12 checks, 0 failures | c76c464cbccf27ce3f32525179bae55fc0c90d6a4a5cc27cc6e3659c7955d10e | a27ffcc1284430158715ceff6ae69aab5fd85bb135d568b7afbf2570063ac1b1 |
| salvage | salvage: 70 checks, 0 failures | f13a4384383a3e0b0aaff49c4840d6263b9b4157cf6d41ded6da9010033d5f37 | 1068ebd316de0aa20703e3a626421e513fd93ae49eff7074e187147a5e89e0cb |
| salvage_voyage | salvage voyage: 14 checks, 0 failures | 2a99bb81b3f30e46a535ca5dd0f75c7de164cb45695d4c0c56480c821f0af161 | 0712833ed78d2ee023ad0c626b29a4eed8f1336554a2038bd4a17d562b196327 |
| voyage_jobs | voyage_jobs: 69 checks, 0 failures | 0792645f46bb40b748b7e5836ac8cc4ae2a74b0dac439456c6331f20cb020530 | 1f79e6eaa4fe831ebb3999ba5940bafc33a42689643e771aba8dacc5afc6e728 |
| voyage_flow | voyage flow: 12 checks, 0 failures | 1586992a5909617f76cece35b2b6853eba154197e1fa39ef59eb69eac94e0a36 | 2deff42d719a09284b1f7568a6b0e3db5900c77892b804b382749d1ff8e07cec |
| factions | ALL FACTION TESTS PASSED (193 checks in 5 ms) | b74ae22407997ee909069ff23a8af451155c81a7009d6dcc3ec6cdf43047a4ea | 98262769952d19ad75212cbf089df8d393978f9867cd33010e472635f86a5763 |
| political_voyage | political voyage: 16 checks, 0 failures | 92b0b8d54885f6179ad580794dab2cb9a1f3199f5af6edb1bf8096e589258e35 | 9bb344c3503102ec9f84564b10e118abe93299a9595c5de14f6b52b0d2460ba3 |
| naval_ai | naval_ai: 227 checks, 0 failures, 2452 ms | f81814e6f660e58102706468edbc6e330c9ca2bab229a7da1f57f856778fdc0d | 250cb5c75b5d75c3620529dd2935ae17b81178aba574b62de59aedc225fb7e71 |
| naval_voyage | naval voyage: 8 checks, 0 failures | 95ceba847039cd2343efc25bbc62ed2a702713e622fd9a6329e6adfdec86a093 | 8e5c1733f0046f4d7a1a670d115315acd676d68eda8798c7f1b29b4c19c1c6de |
| trade_intel | ALL TRADE INTEL TESTS PASSED (67 checks in 16 ms) | f8e0970ecd39cd4427dd5f36780866604f7e5b8dd46ea4f719690f0202dbd844 | ed1d40509ee4d9050f2623a8bc21c98cc9713959e7a762e353ca2d4e27fb8621 |
| reactive_trade | reactive trade: 9 checks, 0 failures | f274308ffa44b417d811225fbaee4dfa233ceefce891278da9f77201ac9f38db | 3b784af180bf90cdc925aca6cbbe877a5bec519bb247deb1c3028a1195e83121 |
| fleet_identity | fleet_identity: 55 checks, 0 failures | d2940273d5cbf180d3d8aa375592e82d5f8f0eeaa7acaa3c0e28beaeb5718ed5 | 3fba9993121c9f043adb9e4dd58d7b942ae062af5c5426c7725b0c8851f26c21 |
| support_voyage | support voyage: 17 checks, 0 failures | 8097b5f008bcbc262a09f23e2435241ee8bae2b3153b77e62a7c3e629ef029a9 | c20f8c0444e9024d19a98e8585f5a1461b809961e3100eaab5514ffcb71af788 |
| naval_recovery | naval recovery: 11 checks, 0 failures | b2fc521f405825c05c50893a017a7afb4112c7bc724da741bf060d87276b2861 | 961dbe0ef8add492ec68eb40ac413da38fa03a212c18ca0ecdfb05a78b0208e6 |
| coastal_stories | coastal_stories: 109 checks, 0 failures | 714de8dd89dc4d401bbf95aeca16ccf1baa5395cdf6c0052b25a764cecf551af | 0b45fccd860677af2a4bf5587e1d07647c96f67dee2851630a67355649ee6a24 |
| story_voyage | story voyage: 18 checks, 0 failures | 41d2731875033d6a3d9f5a7b36bad396427ccb07d48d2ff41841403d05ff38d8 | 00361dd8978598167c941258155ea4b84cfa75d9a74d414a2c1b580f60f4995c |
| home_harbor | home_harbor: 74 checks, 0 failures | 7f091b0a82ff5c0d4d5d514dabe208394f402942e2653807bc7fb71464094922 | 6a05ecba585cdbeb9db3307c31ae39996b52f321278c7eee1772cb2bfbdb5374 |
| home_voyage | home voyage: 17 checks, 0 failures | d539b03e155250b04c3474d6607bb1a779deba97c7935ef9109cc0cf079057ff | a9b09acf7cf97e957305becb8d06220ab45e1b3937ca610e8ce681c73f20d728 |
| regional_campaigns | regional campaigns: 64 checks, 0 failures | 87459cb45dc6528f30f104346d8d7b233dc174d71ba103cfc45e7279ff0b027c | 300c2eac9893678d28fc877bd0945eb2a4badc86f3a5d3a103e84f1c415a5faa |
| regional_voyage | regional voyage: 24 checks, 0 failures | 0f3ecdac9b7c92c9b39606389a62e19b521ca9acfc8af734d61fe236ea5edce0 | a1a414033d70d8de77da7c1f75c3bba16aa35e4e2120a42c93bd38a93ead5a6e |
| campaign_endurance | campaign endurance: 2168 checks, 0 failures, 15291 ms, 8 worker lanes | 046f57dd8047a687c9904e5951134cb96f3a5bbabe2523f724cdf43c4302f69e | 938d63db6f5db40f9256fdea6510dcee36c7f92284b6ba58c0835b00596ca524 |
| crew_training | crew training: 20 checks, 0 failures | 761e731bf289584f243b159bd3ededdfd6413d6b69ba40d0b25ebbd2a414d012 | dbe6d7f5f514531accdbfb7230dc38a91254ca82755c7a3b7062fd1bd1da11bf |
| training_voyage | training voyage: 14 checks, 0 failures | b350512536c9c216fb4ee3091338d0507110fa5bafcb6b315e5a85bd124f604a | c5f72de81545e885c3c77c9715685c1cc5f49cd1cffb6f1e01e734ab146075e2 |
| harbor_reserves | PASS: harbor reserve invariants | 55788dc63c89c270a485eb333e286423b6c1bf8db631af422de4369fe0885029 | 2f8fe02ff5f6a7f771164ab516c1c63344a916c98d41e7605286f22861bc3539 |
| supply_voyage | supply voyage: 12 checks, 0 failures | 1af1c0dc725daa49a293b5bf22caeb4dec7957f414728d436d6098ce346b0bc7 | fd936afa0e936e95c9c6b7fd564cf90032f19746256ba5c392429ee14eed27cc |
| industrial_tooling | PASS industrial_tooling | 070813eb07accc874d45d1b24e804eeef7d79e212a57bd84459fe8a2881bb027 | e13b1d5ece965be3308a13cff78d2b7d1b992b523260466c55adeb5de23543d3 |
| industrial_voyage | industrial voyage: 35 checks, 0 failures | ebe4383b7ef16bf2efd3c63aaa15787d484f14bd2354a10c6c9fb2ca957da9ac | 9ef74aae9e70eb9951edaeb49d8c0c03269a9f6663ca2c5e6fa7de232670607e |
| worker_conditions | worker_conditions: 54 checks, 0 failures | 56ca368f1010188571f949d3d604dae2f72a1c290a5c1fadc2b7d6b8f97f5128 | 05763b15b75c9060962731f56fb31c07771927a04f9996aae84a1ef3b3b82a79 |
| conditions_voyage | conditions voyage: 21 checks, 0 failures | 685cf4b30fb9487991c7509bf92f0e61f58f4d82a07fffd808b0db475b765454 | 1fa2c1804e2cb35f26bdd61392b8379e28e9df324b723741cb17f9f8dc2be84c |
| regional_goods | REGIONAL_GOODS_TESTS_PASS | 60b83c42be8a28b1d126805403ac807fd02441f5156374f34fee33b370c4b7b5 | 4e5e41fda07a8c289d7555818ec7bde437353167e2c2007db698fac9d2189a40 |
| civilian_voyage | civilian voyage: 53 checks, 0 failures | fcb704a1df0db6255d096399723526f9ed86c672780eeb421b2f128f78f56049 | fc962a909f0342d8d2e91636c17da6b6503014745f4a3f3437baea99e3ae1906 |
| shipping_companies | shipping: 0 failures | 7746ce4743ee738a02b60027c18f469a8aa22830d88e5aa7a9c15e9be251a9cd | b096cab43f52787407f5112a9de94a74d5a8e41101379c9916500907e33349d7 |
| company_voyage | company voyage: 30 checks, 0 failures | 3c7c2a62dcdf41c6732a132e4c7625c3eff297d4732d70f02eb542dcb3e0f905 | df80c85a0f77f382f670136cc5b3a5bbc627e94599bcbc1e433b8e35c16bee2a |
| trade_law | trade law: 49 checks, 0 failures; native candidate | c4f5ac0e72ffcc9a5fdb68375cbe97babe5f45435901d95926a4aa6d75ac3165 | d02f6ae0740513c91651c97b11e2317e222492b3f39171e503bc499fd106994d |
| customs_voyage | customs voyage: 25 checks, 0 failures | e31869eca6e72a3b81d5587c2cf5580e1c6b2fc93e8033ddafadbfade61a36b4 | 464fed52e73be9cf3adf3f680eef8dcd379d9c567984dc22e203aa45e85e9ae7 |
| boarding | boarding: 115 checks, 0 failures | 3501600e624b600ec049c6d0a0f7a00dfca633331a5a7dac736f095b16bde2ff | b8e8f9430eb45fe4cf35b4ba2b761bb515d0915af2d7fdc1dddada1b48257912 |
| boarding_voyage | boarding voyage: 28 checks, 0 failures | 327a0a4736a83f81fc9aeecb935a0557beb8c1bcbe053e963e8be27f4086abcb | f6c3312cfa9c3ffb0a0f62a1d3969162346e08f76d31fc97901f6283bbfd57d6 |
| regional_crises | regional_crises: 103 checks; 0 failures | e7483d5f99b757fcab7ee50bd153c369c667aec2ec5c26256ceaf57add88072c | d25c9a5b9d04cb2d6e64ddfec11abd9fe5890af508176878f5856ca2fa8c1758 |
| crisis_voyage | crisis voyage: 30 checks, 0 failures | 38ef6e9bfac6bc4a002a9dc3e063c7f229ba8876210aa01766fc574647ef1964 | 62812c457ea1e05eac0a893712854fef44c41c4a58abfa62498803aec90bc92f |
| campaign_guidance | campaign guidance: 287 checks, 0 failures | 5e722e554995735112b730fb940c79278c0764ec0d3bd13e5c3fbdba525654a0 | 57bdcf0e547b49fb1d538f30fe02f2b128330c10ab0a2432a5e70d429c8d2a22 |
| campaign_systems | campaign systems: 97 checks, 0 failures | 155d2c4bac8d736b28e5ec4a9b5bcb33be582a3a85bde242ec629d4ca30e191f | b2377ab74244aaed58620ab0bcec5142a03fec214108af1669f21c70ea93b0b5 |
| workshop | Workshop: 85 checks, 0 failures | 919c938c253f194c61c582c7f082b31d917c5795598c916b7521d479c8b3437a | 3cc050abf043e1021e81af1aeacc0404e4e2392bb0f12c8f2ca3b4ad60a4e4dd |
| art_workshop | ART WORKSHOP: 2343 checks, 0 failures; max 738 near / 219 far primitives | 022c65f0d10b05ad2f02426594a771801022949eada52ff50d4cadc459c2d78a | 2134ea4b13a725a244b6362c3a33ccfcbb66e4d5724964499205b734a5df7b14 |
| workshop_voyage | workshop voyage: 154 checks, 0 failures | f485bc4c632dd1e474048223fd5468bc92f452d24c90e007f62e9f05345b6e97 | 2ecc66bde320e13570e39118c8cc32c2e177f71b784262279477f9e845491c51 |
| workshop_ui | workshop UI: 69 checks, 0 failures; native controls only, background/headless/silent | 636d5c655212fd2edaf5305214f32c314ca8d029c68fef88b8ea96aadfb91016 | 1c9d6ffe27154deb3bd5320ac8e765cfca298c8543de74218a2bff84209dda85 |

These are imported native logs, not a fresh run by this tool. Lead must verify they match the integrated source and authorized serialized headless/silent run.

Exact-tag Windows export/startup/save/battle, archive hashes, launcher, remote publication, visual/motion review and listening require their own evidence. Source logs establish none of those outcomes.
<!-- brass-tide-series:29:end -->

