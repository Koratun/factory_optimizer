import 'package:json_annotation/json_annotation.dart';

part 'item_recipe.g.dart';

@JsonSerializable()
class ItemRecipe {
  ItemRecipe(this.input, this.output, this.rate, this.building);

  List<ItemAmount> input;
  List<ItemAmount> output;
  double rate;
  // rate is in primary output items per minute
  String? building;
  // Minimum required building to create item

  double? get operationalRate {
    if (output.isEmpty || rate <= 0 || output.first.amount <= 0) {
      return null;
    }
    return rate / output.first.amount;
  }

  factory ItemRecipe.fromJson(Map<String, dynamic> json) =>
      _$ItemRecipeFromJson(json);

  Map<String, dynamic> toJson() => _$ItemRecipeToJson(this);
}

@JsonSerializable()
class ItemAmount {
  ItemAmount(this.name, this.amount, {this.byproduct = false});

  String name;
  // name should match filenames used to save the images
  double amount;
  // amount is items consumed or produced per operation
  bool byproduct;

  factory ItemAmount.fromJson(Map<String, dynamic> json) =>
      _$ItemAmountFromJson(json);

  Map<String, dynamic> toJson() => _$ItemAmountToJson(this);
}
