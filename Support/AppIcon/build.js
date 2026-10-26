#!/usr/bin/env node
// Renders AppIcon.svg into AppIcon.appiconset and AppIcon.icns. Needs playwright + chromium.
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
(async () => {
  const svg = fs.readFileSync(path.join(__dirname, 'AppIcon.svg'), 'utf8');
  const out = path.join(__dirname, 'AppIcon.appiconset'); fs.mkdirSync(out, { recursive: true });
  const b = await chromium.launch(); const pg = await b.newPage(); const png = {};
  for (const s of [16, 32, 64, 128, 256, 512, 1024]) {
    await pg.setViewportSize({ width: s, height: s });
    const sized = svg.replace('width="1024" height="1024"', `width="${s}" height="${s}"`);
    await pg.setContent(`<body style="margin:0;background:transparent">${sized}</body>`);
    png[s] = await pg.screenshot({ omitBackground: true, clip: { x: 0, y: 0, width: s, height: s } });
  }
  await b.close();
  const images = [];
  for (const pt of [16, 32, 128, 256, 512]) for (const sc of [1, 2]) {
    const name = `icon_${pt}x${pt}${sc === 2 ? '@2x' : ''}.png`;
    fs.writeFileSync(path.join(out, name), png[pt * sc]);
    images.push({ idiom: 'mac', size: `${pt}x${pt}`, scale: `${sc}x`, filename: name });
  }
  fs.writeFileSync(path.join(out, 'Contents.json'), JSON.stringify({ images, info: { author: 'xcode', version: 1 } }, null, 2) + '\n');
  const types = [['icp4',16],['icp5',32],['icp6',64],['ic07',128],['ic08',256],['ic09',512],['ic10',1024],['ic11',32],['ic12',64],['ic13',256],['ic14',512]];
  const chunks = types.map(([t, s]) => { const h = Buffer.alloc(8); h.write(t, 0, 'ascii'); h.writeUInt32BE(png[s].length + 8, 4); return Buffer.concat([h, png[s]]); });
  const body = Buffer.concat(chunks); const h = Buffer.alloc(8); h.write('icns', 0, 'ascii'); h.writeUInt32BE(body.length + 8, 4);
  fs.writeFileSync(path.join(__dirname, 'AppIcon.icns'), Buffer.concat([h, body]));
})();
