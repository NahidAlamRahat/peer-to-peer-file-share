const fs = require('fs');
const path = require('path');
const folder = 'D:\\rahat';
function b64(f){return 'data:image/jpeg;base64,'+fs.readFileSync(path.join(folder,f)).toString('base64');}
const img1=b64('1.jpeg'),img2=b64('2.jpeg'),img3=b64('3.jpeg'),img4=b64('4.jpeg'),img5=b64('5.jpeg');

const css = `
@import url('https://fonts.googleapis.com/css2?family=Noto+Sans+Bengali:wght@400;600;700&display=swap');
*{margin:0;padding:0;box-sizing:border-box;}
body{font-family:'Noto Sans Bengali',sans-serif;font-size:12pt;color:#111;background:#ccc;}
.sheet{
  width:210mm;min-height:297mm;margin:12mm auto;padding:20mm 22mm;
  background:#fff;box-shadow:0 4px 24px rgba(0,0,0,0.2);
  page-break-after:always;break-after:page;
  display:flex;flex-direction:column;
}
.sheet:last-child{page-break-after:auto;break-after:auto;}
h1{font-size:22pt;text-align:center;margin-bottom:8px;}
h2{font-size:14pt;margin:22px 0 8px;border-bottom:2.5px solid #222;padding-bottom:4px;}
h3{font-size:12pt;margin:14px 0 5px;color:#333;}
p{line-height:1.85;margin-bottom:9px;text-align:justify;}
ul,ol{padding-left:26px;line-height:1.85;margin-bottom:10px;}
table{width:100%;border-collapse:collapse;margin:12px 0;font-size:11pt;}
th{background:#222;color:#fff;padding:7px 10px;text-align:left;}
td{border:1px solid #ccc;padding:6px 10px;}
tr:nth-child(even) td{background:#f5f5f5;}
.title-box{text-align:center;border:2px solid #222;padding:24px;margin-bottom:24px;border-radius:4px;}
.info-box{border:1px solid #bbb;padding:14px 18px;border-radius:4px;line-height:2.1;margin-top:20px;}
.info-box b{display:inline-block;min-width:160px;}
.code{background:#f3f3f3;border-left:4px solid #555;padding:10px 14px;font-family:monospace;font-size:10pt;white-space:pre;margin:8px 0;border-radius:3px;}
.screen-wrap{text-align:center;margin:14px 0;}
.screen-wrap img{width:180px;border:1.5px solid #ddd;border-radius:14px;box-shadow:0 3px 12px rgba(0,0,0,0.13);}
.caption{font-style:italic;font-size:10pt;color:#555;margin-top:6px;}
.screens-row{display:flex;justify-content:center;gap:20px;flex-wrap:wrap;margin:16px 0;}
.page-label{font-size:9pt;color:#aaa;text-align:right;margin-top:auto;padding-top:10px;}
.section-intro{color:#555;font-size:11pt;margin-bottom:14px;}
@media print{
  body{background:#fff;}
  .sheet{margin:0;box-shadow:none;width:100%;min-height:100vh;padding:18mm 20mm;}
}`;

const pages = [
/* PAGE 1 — Cover */
`<div class="sheet">
  <div style="flex:1;display:flex;flex-direction:column;justify-content:center;align-items:center;">
    <div class="title-box" style="width:100%">
      <h1 style="font-size:26pt;margin-bottom:10px;">অ্যাসাইনমেন্ট</h1>
      <p style="font-size:14pt;font-weight:600;">বিষয়: Peer-to-Peer (P2P)<br>ফাইল শেয়ারিং অ্যাপ্লিকেশন</p>
    </div>
    <div class="info-box" style="width:100%;margin-top:30px;">
      <p><b>শিক্ষার্থীর নাম:</b> [তোমার নাম]</p>
      <p><b>কোর্স:</b> [তোমার কোর্সের নাম]</p>
      <p><b>বিভাগ:</b> [তোমার বিভাগ]</p>
      <p><b>তারিখ:</b> ২২ এপ্রিল, ২০২৬</p>
    </div>
  </div>
  <div class="page-label">পৃষ্ঠা ১</div>
</div>`,

/* PAGE 2 — ভূমিকা + উদ্দেশ্য */
`<div class="sheet">
  <h2>১. ভূমিকা (Introduction)</h2>
  <p>আধুনিক ডিজিটাল যুগে ফাইল শেয়ারিং একটি অত্যন্ত গুরুত্বপূর্ণ প্রয়োজনীয়তা। বর্তমানে Google Drive, WeTransfer বা Telegram-এর মতো সার্ভার-নির্ভর প্ল্যাটফর্মগুলো ব্যবহার করে ফাইল শেয়ার করতে হয়। এতে ফাইলটি প্রথমে একটি কেন্দ্রীয় সার্ভারে আপলোড হয়, তারপর অন্যজন ডাউনলোড করেন। এই পদ্ধতিতে গোপনীয়তা লঙ্ঘনের ঝুঁকি থাকে, ফাইলের সাইজ সীমাবদ্ধতা থাকে এবং সার্ভার খরচ বেশি হয়।</p>
  <p>এই সমস্যাগুলো সমাধান করতে আমি একটি <strong>Peer-to-Peer (P2P) ফাইল শেয়ারিং অ্যাপ্লিকেশন</strong> তৈরি করেছি। এই অ্যাপে দুইটি ডিভাইস সরাসরি একে অপরের সাথে সংযুক্ত হয়ে ফাইল আদান-প্রদান করতে পারে — কোনো মধ্যস্থতাকারী সার্ভারে ফাইল সংরক্ষণ ছাড়াই।</p>
  <h2>২. প্রজেক্টের উদ্দেশ্য (Objective)</h2>
  <p class="section-intro">এই প্রজেক্টের মূল উদ্দেশ্যগুলো হলো:</p>
  <ul>
    <li>ইন্টারনেটের মাধ্যমে দুটি ডিভাইসের মধ্যে সরাসরি ফাইল ট্রান্সফার করা</li>
    <li>কোনো ফাইল সাইজ সীমা ছাড়াই যেকোনো ফাইল পাঠানো</li>
    <li>ফাইল ট্রান্সফারে End-to-End Encryption নিশ্চিত করা</li>
    <li>QR কোড বা লিংক শেয়ারের মাধ্যমে সহজে সংযোগ স্থাপন করা</li>
    <li>Android, iOS, Web, Windows, macOS, Linux — সকল প্ল্যাটফর্মে কাজ করা</li>
  </ul>
  <div class="page-label">পৃষ্ঠা ২</div>
</div>`,

/* PAGE 3 — Technology */
`<div class="sheet">
  <h2>৩. ব্যবহৃত প্রযুক্তি ও ভাষাসমূহ</h2>
  <h3>৩.১ প্রোগ্রামিং ভাষা</h3>
  <table><tr><th>ভাষা</th><th>ব্যবহার</th></tr>
    <tr><td><strong>Dart</strong></td><td>সম্পূর্ণ অ্যাপের মূল কোড লেখা হয়েছে Dart ভাষায়</td></tr>
    <tr><td><strong>JavaScript / Node.js</strong></td><td>Signaling Server তৈরিতে ব্যবহার করা হয়েছে</td></tr>
  </table>
  <h3>৩.২ Framework ও Platform</h3>
  <p><strong>Flutter</strong> — Google-এর তৈরি এই ফ্রেমওয়ার্ক একটি মাত্র কোডবেস থেকে Android, iOS, Web, Windows, macOS এবং Linux সব প্ল্যাটফর্মে অ্যাপ চালাতে পারে।</p>
  <h3>৩.৩ মূল লাইব্রেরিসমূহ</h3>
  <table>
    <tr><th>লাইব্রেরি</th><th>কাজ</th></tr>
    <tr><td>flutter_webrtc ^1.3.1</td><td>WebRTC প্রোটোকল — P2P সংযোগ তৈরি</td></tr>
    <tr><td>flutter_bloc ^9.1.1</td><td>State Management (BLoC Pattern)</td></tr>
    <tr><td>web_socket_channel ^3.0.3</td><td>Signaling Server-এর সাথে WebSocket সংযোগ</td></tr>
    <tr><td>file_picker ^10.3.10</td><td>ডিভাইস থেকে ফাইল নির্বাচন</td></tr>
    <tr><td>qr_flutter ^4.1.0</td><td>QR Code তৈরি</td></tr>
    <tr><td>permission_handler ^12.0.1</td><td>Android/iOS পারমিশন ম্যানেজমেন্ট</td></tr>
    <tr><td>flutter_local_notifications ^21.0.0</td><td>ট্রান্সফার প্রোগ্রেস নোটিফিকেশন</td></tr>
    <tr><td>path_provider ^2.1.5</td><td>ফাইল সেভ করার পাথ নির্ধারণ</td></tr>
    <tr><td>shared_preferences ^2.5.4</td><td>Settings সংরক্ষণ</td></tr>
    <tr><td>wakelock_plus ^1.5.1</td><td>ট্রান্সফারের সময় স্ক্রিন বন্ধ না হওয়া নিশ্চিত করা</td></tr>
    <tr><td>get_it ^9.2.1</td><td>Dependency Injection</td></tr>
    <tr><td>uuid ^4.5.3</td><td>প্রতিটি ফাইলের জন্য ইউনিক আইডি তৈরি</td></tr>
  </table>
  <h3>৩.৪ Deployment Platform</h3>
  <table>
    <tr><th>সেবা</th><th>ব্যবহার</th></tr>
    <tr><td><strong>Render</strong></td><td>Node.js Signaling Server হোস্ট করা হয়েছে</td></tr>
    <tr><td><strong>Vercel</strong></td><td>Web অ্যাপ হোস্ট করা হয়েছে</td></tr>
  </table>
  <div class="page-label">পৃষ্ঠা ৩</div>
</div>`,

/* PAGE 4 — Architecture */
`<div class="sheet">
  <h2>৪. অ্যাপের আর্কিটেকচার (Architecture)</h2>
  <p>এই প্রজেক্টে <strong>Clean Architecture</strong> এবং <strong>BLoC Pattern</strong> অনুসরণ করা হয়েছে।</p>
  <h3>৪.১ লেয়ার বিভাজন</h3>
  <div class="code">lib/
├── core/             ← Theme, DI, Services
├── data/
│   ├── datasources/  ← WebRTC Client, Signaling Service
│   └── repositories/ ← File Transfer Repository
├── domain/
│   ├── entities/     ← ShareFile, FileChunkInfo, PeerSession
│   └── repositories/ ← Abstract Repository Interfaces
└── presentation/
    ├── blocs/        ← ConnectionBloc, TransferBloc
    ├── screens/      ← HomeScreen, ShareLinkScreen, ReceiveScreen, TransferScreen
    └── widgets/      ← Reusable UI components</div>
  <h3>৪.২ কিভাবে কাজ করে</h3>
  <p><strong>ধাপ ১ — Signaling (সংযোগ স্থাপন):</strong></p>
  <ol>
    <li>Sender অ্যাপ খুলে "Send Files" বাটনে ক্লিক করে</li>
    <li>Signaling Server একটি ইউনিক Session ID তৈরি করে</li>
    <li>Sender সেই QR Code বা লিংক Receiver-কে পাঠায়</li>
    <li>Receiver স্ক্যান করলে WebRTC Handshake হয় (Offer → Answer → ICE Candidates)</li>
  </ol>
  <p><strong>ধাপ ২ — File Transfer (ডেটা ট্রান্সফার):</strong></p>
  <ol>
    <li>WebRTC DataChannel খোলে</li>
    <li>ফাইলটি ১৬KB চাংকে ভাগ করে পাঠানো হয়</li>
    <li>প্রতিটি চাংক Receiver-এ জোড়া লাগানো হয়</li>
    <li>সম্পূর্ণ ফাইল পেলে অটোমেটিক সেভ হয়</li>
    <li>Signaling Server-এ কোনো ফাইল ডেটা যায় না</li>
  </ol>
  <div class="page-label">পৃষ্ঠা ৪</div>
</div>`,

/* PAGE 5 — Problems & Solutions */
`<div class="sheet">
  <h2>৫. মূল সমস্যাসমূহ ও সমাধান</h2>
  <h3>সমস্যা ১: NAT Traversal</h3>
  <p><strong>সমস্যা:</strong> বেশিরভাগ ডিভাইস NAT-এর পিছনে থাকে, সরাসরি IP খুঁজে পাওয়া যায় না।</p>
  <p><strong>সমাধান:</strong> একাধিক Google STUN Server ব্যবহার। STUN Server Public IP ও Port বের করে দেয়।</p>
  <h3>সমস্যা ২: Signaling Server Disconnect</h3>
  <p><strong>সমস্যা:</strong> Render Free Tier-এ Server নিষ্ক্রিয়তায় Sleep Mode-এ যায়, 404 Error দেখায়।</p>
  <p><strong>সমাধান:</strong> Exponential Backoff Reconnection (৩s→৬s→১২s→২৪s→৩০s) এবং প্রতি ২০ সেকেন্ডে Heartbeat Ping/Pong।</p>
  <h3>সমস্যা ৩: বড় ফাইলে Memory Overflow</h3>
  <p><strong>সমস্যা:</strong> ১GB+ ফাইল একসাথে মেমোরিতে লোড করলে অ্যাপ ক্র্যাশ করে।</p>
  <p><strong>সমাধান:</strong> ফাইল ১৬KB Chunk-এ কেটে পাঠানো হয়। Buffer &gt; 1MB হলে pause করে। UI ১০০ms-এ Throttle।</p>
  <h3>সমস্যা ৪: Transfer State UI রিসেট না হওয়া</h3>
  <p><strong>সমস্যা:</strong> ট্রান্সফার শেষেও "Active Transfer" ব্যানার স্ক্রিনে থেকে যাচ্ছিল।</p>
  <p><strong>সমাধান:</strong> BLoC-এ ResetTransferEvent যোগ করা হয়েছে। ✕ বাটনে ক্লিক করে dismiss করা যায়।</p>
  <h3>সমস্যা ৫: Multi-platform File Saving</h3>
  <p><strong>সমস্যা:</strong> Android, iOS, Web এবং Desktop-এ ফাইল সেভের পদ্ধতি ভিন্ন।</p>
  <p><strong>সমাধান:</strong> Conditional Import ব্যবহার। Web-এ Browser download API, Mobile/Desktop-এ path_provider।</p>
  <div class="page-label">পৃষ্ঠা ৫</div>
</div>`,

/* PAGE 6 — Security + Platform */
`<div class="sheet">
  <h2>৬. নিরাপত্তা বিশ্লেষণ (Security)</h2>
  <h3>৬.১ End-to-End Encryption</h3>
  <p>WebRTC <strong>DTLS-SRTP</strong> Encryption স্বয়ংক্রিয়ভাবে সমস্ত DataChannel ট্র্যাফিক এনক্রিপ্ট করে। ফলে মাঝপথে কেউ ডেটা চুরি করতে পারে না।</p>
  <ul>
    <li><strong>DTLS:</strong> Connection স্থাপনের সময় Certificate যাচাই করে</li>
    <li><strong>SRTP:</strong> ডেটা ট্রান্সফারের সময় এনক্রিপশন নিশ্চিত করে</li>
  </ul>
  <h3>৬.২ No Server Storage</h3>
  <p>Signaling Server শুধুমাত্র সংযোগ স্থাপনে সাহায্য করে। <strong>কোনো ফাইলের ডেটা সার্ভারে যায় না।</strong> ফাইল সরাসরি Sender থেকে Receiver-এ যায়।</p>
  <h3>৬.৩ Session-based Access Control</h3>
  <p>প্রতিটি ট্রান্সফারের জন্য ইউনিক Session ID তৈরি হয়। এই ID না জানলে কেউ সংযোগ করতে পারে না।</p>
  <h2>৭. প্ল্যাটফর্ম সমর্থন</h2>
  <table>
    <tr><th>প্ল্যাটফর্ম</th><th>সমর্থন</th></tr>
    <tr><td>Android</td><td>✅ সম্পূর্ণ সমর্থিত</td></tr>
    <tr><td>iOS</td><td>✅ সমর্থিত</td></tr>
    <tr><td>Web (Browser)</td><td>✅ সমর্থিত — Vercel-এ Deployed</td></tr>
    <tr><td>Windows</td><td>✅ সমর্থিত</td></tr>
    <tr><td>macOS</td><td>✅ সমর্থিত</td></tr>
    <tr><td>Linux</td><td>✅ সমর্থিত</td></tr>
  </table>
  <p>Flutter ব্যবহারের ফলে একটি কোডবেস থেকেই সকল প্ল্যাটফর্মে অ্যাপ চালানো সম্ভব হয়েছে।</p>
  <div class="page-label">পৃষ্ঠা ৬</div>
</div>`,

/* PAGE 7 — Screenshots (Home + Share) */
`<div class="sheet">
  <h2>৮. অ্যাপের স্ক্রিনসমূহ (App Screenshots)</h2>
  <p class="section-intro">নিচে অ্যাপ্লিকেশনের বিভিন্ন স্ক্রিনের বাস্তব Screenshot দেওয়া হলো:</p>
  <div class="screens-row">
    <div class="screen-wrap">
      <img src="${img1}" alt="Home Screen">
      <p class="caption">চিত্র ১: Home Screen<br>"Send Files" ও "Receive Files" বাটন</p>
    </div>
    <div class="screen-wrap">
      <img src="${img2}" alt="Share File Screen">
      <p class="caption">চিত্র ২: Share File Screen<br>QR Code ও Session Code (191393)</p>
    </div>
  </div>
  <div class="page-label">পৃষ্ঠা ৭</div>
</div>`,

/* PAGE 8 — Screenshots (Receive + Transfer + Complete) */
`<div class="sheet">
  <h2>৮. অ্যাপের স্ক্রিনসমূহ (চলমান)</h2>
  <div class="screens-row">
    <div class="screen-wrap">
      <img src="${img5}" alt="Receive File Screen">
      <p class="caption">চিত্র ৩: Receive File Screen<br>Download বাটন</p>
    </div>
    <div class="screen-wrap">
      <img src="${img4}" alt="Live Transfer Screen">
      <p class="caption">চিত্র ৪: Live Transfer Screen<br>রিয়েল-টাইম Progress — 927.5 KB/s</p>
    </div>
    <div class="screen-wrap">
      <img src="${img3}" alt="Transfer Complete">
      <p class="caption">চিত্র ৫: Transfer Complete<br>সবুজ চেকমার্ক সহ সফল ট্রান্সফার</p>
    </div>
  </div>
  <div class="page-label">পৃষ্ঠা ৮</div>
</div>`,

/* PAGE 9 — Limitations + Conclusion */
`<div class="sheet">
  <h2>৯. প্রজেক্টের সীমাবদ্ধতা (Limitations)</h2>
  <ol>
    <li><strong>TURN Server অনুপস্থিত:</strong> Symmetric NAT পরিবেশে (অনেক Corporate/University নেটওয়ার্ক) সংযোগ ব্যর্থ হতে পারে।</li>
    <li><strong>একটি Session-এ একজন Receiver:</strong> বর্তমানে একটি লিংক শুধু একজনের সাথে শেয়ার করা যায়।</li>
    <li><strong>Render Free Tier:</strong> দীর্ঘ নিষ্ক্রিয়তায় Signaling Server Sleep Mode-এ যায়।</li>
  </ol>
  <h2>১০. উপসংহার (Conclusion)</h2>
  <p>এই প্রজেক্টটি WebRTC প্রযুক্তি ব্যবহার করে একটি সম্পূর্ণ Peer-to-Peer ফাইল শেয়ারিং সিস্টেম তৈরির সফল উদ্যোগ। এটি প্রমাণ করে যে আধুনিক ওয়েব প্রযুক্তি ব্যবহার করে কোনো কেন্দ্রীয় সার্ভার ছাড়াই নিরাপদ, দ্রুত এবং সীমাহীন ফাইল ট্রান্সফার সম্ভব।</p>
  <p>Flutter ফ্রেমওয়ার্ক ব্যবহার করে একটি কোডবেস থেকে ৬টি প্ল্যাটফর্মে অ্যাপ চালানো, Clean Architecture-এর মাধ্যমে কোড পরিষ্কার রাখা এবং বাস্তব সমস্যাগুলো (NAT Traversal, Reconnection, Buffer Management) সমাধান করা — এই প্রজেক্টের মূল অর্জন।</p>
  <p>ভবিষ্যতে TURN Server যোগ, Multi-peer support এবং File Transfer Password Protection যোগ করলে এটি একটি পূর্ণাঙ্গ প্রোডাকশন-রেডি অ্যাপ্লিকেশন হয়ে উঠবে।</p>
  <hr style="border:none;border-top:1px solid #ddd;margin:20px 0;">
  <p style="text-align:center;font-style:italic;color:#777;font-size:10pt;">GitHub Repo: NahidAlamRahat/peer-to-peer-file-share</p>
  <div class="page-label">পৃষ্ঠা ৯</div>
</div>`
];

const html = `<!DOCTYPE html><html lang="bn"><head><meta charset="UTF-8">
<title>Assignment - P2P File Share</title>
<style>${css}</style></head><body>${pages.join('\n')}</body></html>`;

fs.writeFileSync(path.join(folder,'assignment.html'),html,'utf-8');
console.log('✅ Done! D:\\rahat\\assignment.html');
console.log('👉 Chrome-এ খোলো → Ctrl+P → Save as PDF');
