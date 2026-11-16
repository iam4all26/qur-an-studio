// Generated list of the built-in asset packs.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../store/store_service.dart';

class CatalogItem {
  const CatalogItem(this.path, this.name, {this.tint = false});
  final String path;
  final String name;

  /// Downloaded SVG icons that start white and can be recoloured.
  final bool tint;

  /// True for a downloaded item (stored on the phone) and false for a built-in one.
  bool get isFile => path.startsWith('/');
}

/// Shows a catalog item, whether built in or downloaded.
Widget catalogImage(CatalogItem item, {BoxFit fit = BoxFit.contain, int? cacheWidth}) {
  if (item.isFile) {
    if (item.path.toLowerCase().endsWith('.svg')) {
      return SvgPicture.file(
        File(item.path),
        fit: fit,
        colorFilter: item.tint ? const ColorFilter.mode(Colors.white, BlendMode.srcIn) : null,
      );
    }
    return Image.file(File(item.path), fit: fit, cacheWidth: cacheWidth);
  }
  if (item.path.toLowerCase().endsWith('.svg')) {
    return SvgPicture.asset(item.path, fit: fit);
  }
  return Image.asset(item.path, fit: fit, cacheWidth: cacheWidth);
}

/// Built-in backgrounds plus the ones downloaded from the store, as one list.
List<CatalogItem> allBackgrounds() => [
      ...kBackgrounds,
      for (final i in StoreService.instance.ofType('background')) CatalogItem(i.path, i.name),
    ];

/// Built-in icons plus downloaded icons, as one list.
List<CatalogItem> allIcons() => [
      ...kIcons,
      for (final i in StoreService.instance.ofType('icon')) CatalogItem(i.path, i.name, tint: true),
    ];

/// Downloaded shapes.
List<CatalogItem> storeShapes() => [
      for (final i in StoreService.instance.ofType('shape')) CatalogItem(i.path, i.name),
    ];

const List<CatalogItem> kBackgrounds = [
  CatalogItem('assets/backgrounds/01_Royal_Purple_Waves.jpg', 'Royal Purple Waves'),
  CatalogItem('assets/backgrounds/02_Elegant_White_Waves.jpg', 'Elegant White Waves'),
  CatalogItem('assets/backgrounds/03_White_Geometric_Corners.jpg', 'White Geometric Corners'),
  CatalogItem('assets/backgrounds/04_Whiteboard_Grid.jpg', 'Whiteboard Grid'),
  CatalogItem('assets/backgrounds/05_Dark_Technology.jpg', 'Dark Technology'),
  CatalogItem('assets/backgrounds/06_Educational_Parchment.jpg', 'Educational Parchment'),
  CatalogItem('assets/backgrounds/07_Classroom_Blue.jpg', 'Classroom Blue'),
  CatalogItem('assets/backgrounds/08_Financial_Growth.jpg', 'Financial Growth'),
  CatalogItem('assets/backgrounds/09_Business_Presentation.jpg', 'Business Presentation'),
  CatalogItem('assets/backgrounds/10_Cryptocurrency_Blockchain.jpg', 'Cryptocurrency Blockchain'),
  CatalogItem('assets/backgrounds/11_Video_Production.jpg', 'Video Production'),
  CatalogItem('assets/backgrounds/12_Green_Chalkboard.jpg', 'Green Chalkboard'),
  CatalogItem('assets/backgrounds/13_AI_Innovation.jpg', 'AI Innovation'),
  CatalogItem('assets/backgrounds/14_Nature_Landscape.jpg', 'Nature Landscape'),
  CatalogItem('assets/backgrounds/15_Abstract_Geometric.jpg', 'Abstract Geometric'),
];

const List<CatalogItem> kIcons = [
  CatalogItem('assets/icons/01_Graduation_Cap.png', 'Graduation Cap'),
  CatalogItem('assets/icons/02_Books.png', 'Books'),
  CatalogItem('assets/icons/03_Open_Book.png', 'Open Book'),
  CatalogItem('assets/icons/04_Certificate.png', 'Certificate'),
  CatalogItem('assets/icons/05_School.png', 'School'),
  CatalogItem('assets/icons/06_Laptop.png', 'Laptop'),
  CatalogItem('assets/icons/07_Desktop_Monitor.png', 'Desktop Monitor'),
  CatalogItem('assets/icons/08_Smartphone.png', 'Smartphone'),
  CatalogItem('assets/icons/09_Chip.png', 'Chip'),
  CatalogItem('assets/icons/10_Cloud.png', 'Cloud'),
  CatalogItem('assets/icons/11_Briefcase.png', 'Briefcase'),
  CatalogItem('assets/icons/12_Shop.png', 'Shop'),
  CatalogItem('assets/icons/13_Growth_Chart.png', 'Growth Chart'),
  CatalogItem('assets/icons/14_Handshake.png', 'Handshake'),
  CatalogItem('assets/icons/15_Layers.png', 'Layers'),
  CatalogItem('assets/icons/16_Video.png', 'Video'),
  CatalogItem('assets/icons/17_Camera.png', 'Camera'),
  CatalogItem('assets/icons/18_Microphone.png', 'Microphone'),
  CatalogItem('assets/icons/19_Headphones.png', 'Headphones'),
  CatalogItem('assets/icons/20_Speaker.png', 'Speaker'),
  CatalogItem('assets/icons/21_Naira.png', 'Naira'),
  CatalogItem('assets/icons/22_Dollar.png', 'Dollar'),
  CatalogItem('assets/icons/23_Coins.png', 'Coins'),
  CatalogItem('assets/icons/24_Wallet.png', 'Wallet'),
  CatalogItem('assets/icons/25_Bank.png', 'Bank'),
  CatalogItem('assets/icons/26_Chat.png', 'Chat'),
  CatalogItem('assets/icons/27_Email.png', 'Email'),
  CatalogItem('assets/icons/28_Phone.png', 'Phone'),
  CatalogItem('assets/icons/29_Megaphone.png', 'Megaphone'),
  CatalogItem('assets/icons/30_Notification.png', 'Notification'),
  CatalogItem('assets/icons/31_Atom.png', 'Atom'),
  CatalogItem('assets/icons/32_Flask.png', 'Flask'),
  CatalogItem('assets/icons/33_Microscope.png', 'Microscope'),
  CatalogItem('assets/icons/34_DNA.png', 'DNA'),
  CatalogItem('assets/icons/35_Brain.png', 'Brain'),
  CatalogItem('assets/icons/36_Location.png', 'Location'),
  CatalogItem('assets/icons/37_Compass.png', 'Compass'),
  CatalogItem('assets/icons/38_Map.png', 'Map'),
  CatalogItem('assets/icons/39_Target.png', 'Target'),
  CatalogItem('assets/icons/40_Clock.png', 'Clock'),
  CatalogItem('assets/icons/41_New_Project.png', 'New Project'),
  CatalogItem('assets/icons/42_Folder.png', 'Folder'),
  CatalogItem('assets/icons/43_Play_Preview.png', 'Play Preview'),
  CatalogItem('assets/icons/44_Download.png', 'Download'),
  CatalogItem('assets/icons/45_Upload.png', 'Upload'),
  CatalogItem('assets/icons/46_Settings.png', 'Settings'),
  CatalogItem('assets/icons/47_Security_Shield.png', 'Security Shield'),
  CatalogItem('assets/icons/48_Lock.png', 'Lock'),
  CatalogItem('assets/icons/49_Sync.png', 'Sync'),
  CatalogItem('assets/icons/50_Delete.png', 'Delete'),
];

const List<CatalogItem> kIllustrations = [
  CatalogItem('assets/illustrations/01_Light_Bulb.png', 'Light Bulb'),
  CatalogItem('assets/illustrations/02_Open_Book.png', 'Open Book'),
  CatalogItem('assets/illustrations/03_Laptop.png', 'Laptop'),
  CatalogItem('assets/illustrations/04_Desktop_Monitor.png', 'Desktop Monitor'),
  CatalogItem('assets/illustrations/05_Smartphone.png', 'Smartphone'),
  CatalogItem('assets/illustrations/06_Graduation_Cap.png', 'Graduation Cap'),
  CatalogItem('assets/illustrations/07_Teacher_Presentation.png', 'Teacher Presentation'),
  CatalogItem('assets/illustrations/08_Student_Learning.png', 'Student Learning'),
  CatalogItem('assets/illustrations/09_Teamwork.png', 'Teamwork'),
  CatalogItem('assets/illustrations/10_Settings_Gears.png', 'Settings Gears'),
  CatalogItem('assets/illustrations/11_Growth_Chart.png', 'Growth Chart'),
  CatalogItem('assets/illustrations/12_Target.png', 'Target'),
  CatalogItem('assets/illustrations/13_Rocket.png', 'Rocket'),
  CatalogItem('assets/illustrations/14_Brain.png', 'Brain'),
  CatalogItem('assets/illustrations/15_Money_Bag.png', 'Money Bag'),
  CatalogItem('assets/illustrations/16_Coins.png', 'Coins'),
  CatalogItem('assets/illustrations/17_Globe.png', 'Globe'),
  CatalogItem('assets/illustrations/18_Security_Shield.png', 'Security Shield'),
  CatalogItem('assets/illustrations/19_Calendar.png', 'Calendar'),
  CatalogItem('assets/illustrations/20_Clock.png', 'Clock'),
  CatalogItem('assets/illustrations/21_Checklist.png', 'Checklist'),
  CatalogItem('assets/illustrations/22_Magnifying_Glass.png', 'Magnifying Glass'),
  CatalogItem('assets/illustrations/23_Cloud_Upload.png', 'Cloud Upload'),
  CatalogItem('assets/illustrations/24_Database.png', 'Database'),
  CatalogItem('assets/illustrations/25_Video_Camera.png', 'Video Camera'),
  CatalogItem('assets/illustrations/26_Microphone.png', 'Microphone'),
  CatalogItem('assets/illustrations/27_Headphones.png', 'Headphones'),
  CatalogItem('assets/illustrations/28_Megaphone.png', 'Megaphone'),
  CatalogItem('assets/illustrations/29_Email.png', 'Email'),
  CatalogItem('assets/illustrations/30_Network.png', 'Network'),
];

const List<CatalogItem> kSocialIcons = [
  CatalogItem('assets/brands/social/facebook.svg', 'Facebook'),
  CatalogItem('assets/brands/social/instagram.svg', 'Instagram'),
  CatalogItem('assets/brands/social/youtube.svg', 'YouTube'),
  CatalogItem('assets/brands/social/tiktok.svg', 'TikTok'),
  CatalogItem('assets/brands/social/x.svg', 'X'),
  CatalogItem('assets/brands/social/whatsapp.svg', 'WhatsApp'),
  CatalogItem('assets/brands/social/telegram.svg', 'Telegram'),
  CatalogItem('assets/brands/social/snapchat.svg', 'Snapchat'),
  CatalogItem('assets/brands/social/threads.svg', 'Threads'),
  CatalogItem('assets/brands/social/discord.svg', 'Discord'),
  CatalogItem('assets/brands/social/reddit.svg', 'Reddit'),
  CatalogItem('assets/brands/social/pinterest.svg', 'Pinterest'),
  CatalogItem('assets/brands/social/linkedin.svg', 'LinkedIn'),
];

const List<CatalogItem> kDeveloperIcons = [
  CatalogItem('assets/brands/dev/github.svg', 'GitHub'),
  CatalogItem('assets/brands/dev/gitlab.svg', 'GitLab'),
  CatalogItem('assets/brands/dev/bitbucket.svg', 'Bitbucket'),
  CatalogItem('assets/brands/dev/codepen.svg', 'CodePen'),
  CatalogItem('assets/brands/dev/stackoverflow.svg', 'Stack Overflow'),
  CatalogItem('assets/brands/dev/npm.svg', 'npm'),
  CatalogItem('assets/brands/dev/git.svg', 'Git'),
  CatalogItem('assets/brands/dev/docker.svg', 'Docker'),
  CatalogItem('assets/brands/dev/figma.svg', 'Figma'),
  CatalogItem('assets/brands/dev/firebase.svg', 'Firebase'),
  CatalogItem('assets/brands/dev/flutter.svg', 'Flutter'),
  CatalogItem('assets/brands/dev/android.svg', 'Android'),
  CatalogItem('assets/brands/dev/react.svg', 'React'),
  CatalogItem('assets/brands/dev/nodejs.svg', 'Node.js'),
  CatalogItem('assets/brands/dev/laravel.svg', 'Laravel'),
  CatalogItem('assets/brands/dev/mysql.svg', 'MySQL'),
  CatalogItem('assets/brands/dev/vuejs.svg', 'Vue.js'),
  CatalogItem('assets/brands/dev/wordpress.svg', 'WordPress'),
  CatalogItem('assets/brands/dev/tailwindcss.svg', 'Tailwind CSS'),
];

const List<CatalogItem> kLanguageIcons = [
  CatalogItem('assets/brands/lang/python.svg', 'Python'),
  CatalogItem('assets/brands/lang/javascript.svg', 'JavaScript'),
  CatalogItem('assets/brands/lang/typescript.svg', 'TypeScript'),
  CatalogItem('assets/brands/lang/dart.svg', 'Dart'),
  CatalogItem('assets/brands/lang/java.svg', 'Java'),
  CatalogItem('assets/brands/lang/kotlin.svg', 'Kotlin'),
  CatalogItem('assets/brands/lang/swift.svg', 'Swift'),
  CatalogItem('assets/brands/lang/c.svg', 'C'),
  CatalogItem('assets/brands/lang/cplusplus.svg', 'C++'),
  CatalogItem('assets/brands/lang/csharp.svg', 'C#'),
  CatalogItem('assets/brands/lang/php.svg', 'PHP'),
  CatalogItem('assets/brands/lang/ruby.svg', 'Ruby'),
  CatalogItem('assets/brands/lang/rust.svg', 'Rust'),
  CatalogItem('assets/brands/lang/html5.svg', 'HTML5'),
  CatalogItem('assets/brands/lang/css3.svg', 'CSS3'),
  CatalogItem('assets/brands/lang/r.svg', 'R'),
  CatalogItem('assets/brands/lang/scala.svg', 'Scala'),
  CatalogItem('assets/brands/lang/solidity.svg', 'Solidity'),
  CatalogItem('assets/brands/lang/bash.svg', 'Bash'),
  CatalogItem('assets/brands/lang/sqlite.svg', 'SQLite'),
  CatalogItem('assets/brands/lang/postgresql.svg', 'PostgreSQL'),
];

const List<CatalogItem> kCryptoIcons = [
  CatalogItem('assets/brands/crypto/btc.svg', 'Bitcoin'),
  CatalogItem('assets/brands/crypto/eth.svg', 'Ethereum'),
  CatalogItem('assets/brands/crypto/usdt.svg', 'Tether'),
  CatalogItem('assets/brands/crypto/bnb.svg', 'BNB'),
  CatalogItem('assets/brands/crypto/sol.svg', 'Solana'),
  CatalogItem('assets/brands/crypto/xrp.svg', 'XRP'),
  CatalogItem('assets/brands/crypto/doge.svg', 'Dogecoin'),
  CatalogItem('assets/brands/crypto/trx.svg', 'TRON'),
  CatalogItem('assets/brands/crypto/ltc.svg', 'Litecoin'),
  CatalogItem('assets/brands/crypto/dot.svg', 'Polkadot'),
  CatalogItem('assets/brands/crypto/matic.svg', 'Polygon'),
  CatalogItem('assets/brands/crypto/usdc.svg', 'USD Coin'),
  CatalogItem('assets/brands/crypto/dai.svg', 'Dai'),
  CatalogItem('assets/brands/crypto/avax.svg', 'Avalanche'),
  CatalogItem('assets/brands/crypto/link.svg', 'Chainlink'),
  CatalogItem('assets/brands/crypto/xlm.svg', 'Stellar'),
  CatalogItem('assets/brands/crypto/bch.svg', 'Bitcoin Cash'),
  CatalogItem('assets/brands/crypto/atom.svg', 'Cosmos'),
  CatalogItem('assets/brands/crypto/xmr.svg', 'Monero'),
  CatalogItem('assets/brands/crypto/etc.svg', 'Ethereum Classic'),
  CatalogItem('assets/brands/crypto/eos.svg', 'EOS'),
  CatalogItem('assets/brands/crypto/neo.svg', 'NEO'),
  CatalogItem('assets/brands/crypto/dash.svg', 'Dash'),
  CatalogItem('assets/brands/crypto/zec.svg', 'Zcash'),
  CatalogItem('assets/brands/crypto/xtz.svg', 'Tezos'),
  CatalogItem('assets/brands/crypto/algo.svg', 'Algorand'),
  CatalogItem('assets/brands/crypto/vet.svg', 'VeChain'),
  CatalogItem('assets/brands/crypto/fil.svg', 'Filecoin'),
  CatalogItem('assets/brands/crypto/icp.svg', 'Internet Computer'),
  CatalogItem('assets/brands/crypto/uni.svg', 'Uniswap'),
  CatalogItem('assets/brands/crypto/mkr.svg', 'Maker'),
  CatalogItem('assets/brands/crypto/aave.svg', 'Aave'),
  CatalogItem('assets/brands/crypto/comp.svg', 'Compound'),
  CatalogItem('assets/brands/crypto/sushi.svg', 'SushiSwap'),
  CatalogItem('assets/brands/crypto/crv.svg', 'Curve'),
  CatalogItem('assets/brands/crypto/snx.svg', 'Synthetix'),
  CatalogItem('assets/brands/crypto/yfi.svg', 'yearn.finance'),
  CatalogItem('assets/brands/crypto/sand.svg', 'The Sandbox'),
  CatalogItem('assets/brands/crypto/enj.svg', 'Enjin'),
  CatalogItem('assets/brands/crypto/bat.svg', 'Basic Attention'),
  CatalogItem('assets/brands/crypto/theta.svg', 'Theta'),
  CatalogItem('assets/brands/crypto/ape.svg', 'ApeCoin'),
  CatalogItem('assets/brands/crypto/chz.svg', 'Chiliz'),
  CatalogItem('assets/brands/crypto/ksm.svg', 'Kusama'),
  CatalogItem('assets/brands/crypto/miota.svg', 'IOTA'),
  CatalogItem('assets/brands/crypto/nano.svg', 'Nano'),
  CatalogItem('assets/brands/crypto/waves.svg', 'Waves'),
  CatalogItem('assets/brands/crypto/zil.svg', 'Zilliqa'),
  CatalogItem('assets/brands/crypto/bnt.svg', 'Bancor'),
  CatalogItem('assets/brands/crypto/zrx.svg', '0x'),
  CatalogItem('assets/brands/crypto/omg.svg', 'OMG Network'),
  CatalogItem('assets/brands/crypto/qtum.svg', 'Qtum'),
  CatalogItem('assets/brands/crypto/ont.svg', 'Ontology'),
  CatalogItem('assets/brands/crypto/1inch.svg', '1inch'),
  CatalogItem('assets/brands/crypto/wbtc.svg', 'Wrapped Bitcoin'),
  CatalogItem('assets/brands/crypto/tusd.svg', 'TrueUSD'),
  CatalogItem('assets/brands/crypto/btt.svg', 'BitTorrent'),
  CatalogItem('assets/brands/crypto/hot.svg', 'Holo'),
  CatalogItem('assets/brands/crypto/icx.svg', 'ICON'),
];

// Backgrounds that are mostly dark: new text defaults to white on them.
const Set<String> kDarkBackgrounds = {
  'assets/backgrounds/01_Royal_Purple_Waves.jpg',
  'assets/backgrounds/05_Dark_Technology.jpg',
  'assets/backgrounds/08_Financial_Growth.jpg',
  'assets/backgrounds/10_Cryptocurrency_Blockchain.jpg',
  'assets/backgrounds/11_Video_Production.jpg',
  'assets/backgrounds/12_Green_Chalkboard.jpg',
  'assets/backgrounds/13_AI_Innovation.jpg',
};

const List<CatalogItem> kAppIcons = [
  CatalogItem('assets/brands/apps/googleplay.svg', 'Google Play'),
  CatalogItem('assets/brands/apps/appstore.svg', 'App Store'),
  CatalogItem('assets/brands/apps/apple.svg', 'Apple'),
  CatalogItem('assets/brands/apps/googlechrome.svg', 'Chrome'),
  CatalogItem('assets/brands/apps/firefox.svg', 'Firefox'),
  CatalogItem('assets/brands/apps/safari.svg', 'Safari'),
  CatalogItem('assets/brands/apps/opera.svg', 'Opera'),
  CatalogItem('assets/brands/apps/brave.svg', 'Brave'),
  CatalogItem('assets/brands/apps/linux.svg', 'Linux'),
  CatalogItem('assets/brands/apps/spotify.svg', 'Spotify'),
  CatalogItem('assets/brands/apps/netflix.svg', 'Netflix'),
  CatalogItem('assets/brands/apps/zoom.svg', 'Zoom'),
  CatalogItem('assets/brands/apps/googlemeet.svg', 'Google Meet'),
  CatalogItem('assets/brands/apps/notion.svg', 'Notion'),
  CatalogItem('assets/brands/apps/googledrive.svg', 'Google Drive'),
  CatalogItem('assets/brands/apps/dropbox.svg', 'Dropbox'),
  CatalogItem('assets/brands/apps/gmail.svg', 'Gmail'),
  CatalogItem('assets/brands/apps/googlemaps.svg', 'Google Maps'),
  CatalogItem('assets/brands/apps/uber.svg', 'Uber'),
  CatalogItem('assets/brands/apps/airbnb.svg', 'Airbnb'),
  CatalogItem('assets/brands/apps/twitch.svg', 'Twitch'),
  CatalogItem('assets/brands/apps/vimeo.svg', 'Vimeo'),
  CatalogItem('assets/brands/apps/soundcloud.svg', 'SoundCloud'),
  CatalogItem('assets/brands/apps/applemusic.svg', 'Apple Music'),
  CatalogItem('assets/brands/apps/youtubemusic.svg', 'YouTube Music'),
  CatalogItem('assets/brands/apps/viber.svg', 'Viber'),
  CatalogItem('assets/brands/apps/signal.svg', 'Signal'),
  CatalogItem('assets/brands/apps/wechat.svg', 'WeChat'),
  CatalogItem('assets/brands/apps/line.svg', 'LINE'),
  CatalogItem('assets/brands/apps/shopify.svg', 'Shopify'),
  CatalogItem('assets/brands/apps/ebay.svg', 'eBay'),
  CatalogItem('assets/brands/apps/aliexpress.svg', 'AliExpress'),
];

const List<CatalogItem> kPaymentIcons = [
  CatalogItem('assets/brands/pay/paypal.svg', 'PayPal'),
  CatalogItem('assets/brands/pay/visa.svg', 'Visa'),
  CatalogItem('assets/brands/pay/mastercard.svg', 'Mastercard'),
  CatalogItem('assets/brands/pay/stripe.svg', 'Stripe'),
  CatalogItem('assets/brands/pay/googlepay.svg', 'Google Pay'),
  CatalogItem('assets/brands/pay/applepay.svg', 'Apple Pay'),
  CatalogItem('assets/brands/pay/wise.svg', 'Wise'),
  CatalogItem('assets/brands/pay/cashapp.svg', 'Cash App'),
  CatalogItem('assets/brands/pay/binance.svg', 'Binance'),
  CatalogItem('assets/brands/pay/coinbase.svg', 'Coinbase'),
  CatalogItem('assets/brands/pay/kucoin.svg', 'KuCoin'),
  CatalogItem('assets/brands/pay/okx.svg', 'OKX'),
];
