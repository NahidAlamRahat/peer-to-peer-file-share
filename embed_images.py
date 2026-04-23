import base64

imgs = ['1', '2', '3', '4', '5']
folder = r'D:\rahat'

with open(folder + r'\assignment.md', 'r', encoding='utf-8') as f:
    content = f.read()

for i in imgs:
    img_file = folder + '\\' + i + '.jpeg'
    with open(img_file, 'rb') as f:
        b64 = base64.b64encode(f.read()).decode('utf-8')
    data_uri = 'data:image/jpeg;base64,' + b64

    # Replace absolute path reference
    content = content.replace('](d:/rahat/' + i + '.jpeg)', '](' + data_uri + ')')
    # Replace relative path reference (just in case)
    content = content.replace('](' + i + '.jpeg)', '](' + data_uri + ')')

with open(folder + r'\assignment.md', 'w', encoding='utf-8') as f:
    f.write(content)

print('Done! All', len(imgs), 'images embedded as base64 directly in markdown.')
