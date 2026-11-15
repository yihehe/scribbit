// Optional artwork maintenance tool. Normal builds use committed exports.
// Requires Node.js, Sharp (with SVG filters), and macOS iconutil.
const fs = require('node:fs/promises');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const sharp = require('sharp');

async function main() {
    const root = path.resolve(__dirname, '..');
    const source = path.join(root, 'Resources/Branding');
    const output = path.join(root, 'Sources/Scribbit/Resources');
    const scratch = path.join(root, 'build/branding-export');
    await fs.mkdir(scratch, { recursive: true });
    await fs.mkdir(output, { recursive: true });
    const temporary = await fs.mkdtemp(path.join(scratch, 'export-'));
    const iconset = path.join(temporary, 'AppIcon.iconset');
    await fs.mkdir(iconset);
    const app = await fs.readFile(path.join(source, 'AppIcon.svg'));
    const mark = await fs.readFile(path.join(source, 'FrogPencil.svg'));
    for (const size of [16, 32, 128, 256, 512]) {
        for (const scale of [1, 2]) {
            const filename = `icon_${size}x${size}${scale === 2 ? '@2x' : ''}.png`;
            await sharp(app, { density: 144 }).resize(size * scale, size * scale)
                .png().toFile(path.join(iconset, filename));
        }
    }
    execFileSync('/usr/bin/iconutil', ['-c', 'icns', iconset, '-o', path.join(root, 'Resources/AppIcon.icns')]);
    for (const size of [14, 18]) {
        for (const scale of [1, 2]) {
            await sharp(mark, { density: 144 }).resize(size * scale, size * scale)
                .png().toFile(path.join(output, `FrogPencil-${size}${scale === 2 ? '@2x' : ''}.png`));
        }
    }
    console.log('Exported app icon and 14/18-point template marks. Renderer:', sharp.versions);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
