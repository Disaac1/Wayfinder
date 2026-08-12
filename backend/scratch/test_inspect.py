import os
import sys

sys.path.insert(0, r"c:\Users\disaa\Desktop\Code\Wayfinder\backend\archipelago_core")

from worlds.AutoWorld import AutoWorldRegister

world_class = AutoWorldRegister.world_types.get("Factorio")
if world_class:
    import dataclasses
    import typing
    opt_dataclass = world_class.options_dataclass
    print("Resolved fields:")
    type_hints = typing.get_type_hints(opt_dataclass)
    for field in dataclasses.fields(opt_dataclass):
        field_type = type_hints.get(field.name, field.type)
        print(f"  Field: {field.name}, Resolved Type: {field_type}, isinstance(type): {isinstance(field_type, type)}")
