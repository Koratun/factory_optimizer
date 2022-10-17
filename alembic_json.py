import os, json

for fname in os.listdir("data/Satisfactory/recipes"):
    fullname = os.path.join("data/Satisfactory/recipes", fname)
    with open(fullname, 'r') as f:
        data = json.load(f)
    
    for d in data["input"]:
        d["byproduct"] = False
    for d in data["output"]:
        d["byproduct"] = False

    with open(fullname, 'w') as f:
        json.dump( data, f)