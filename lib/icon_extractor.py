import sys
from icoextract import IconExtractor

PATH, filename = sys.argv[1:3]

extractor = IconExtractor(filename=PATH)
for idx, entry in enumerate(extractor.list_group_icons()):
    eid, offset = entry
    print(f"Index: {idx}    "
            f"ID: {eid}({hex(eid)})    "
            f"Offset: {hex(offset)}")
extractor.export_icon(filename+".png")
