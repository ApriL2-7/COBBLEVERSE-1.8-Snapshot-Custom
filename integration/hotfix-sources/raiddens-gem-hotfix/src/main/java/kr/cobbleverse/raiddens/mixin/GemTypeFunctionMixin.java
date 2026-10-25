package kr.cobbleverse.raiddens.mixin;

import com.necro.raid.dens.common.data.raid.RaidType;
import com.necro.raid.dens.common.loot.function.GemTypeFunction;
import net.minecraft.item.Item;
import net.minecraft.item.ItemStack;
import net.minecraft.registry.Registries;
import net.minecraft.util.Identifier;
import net.minecraft.util.math.random.Random;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

import java.util.Locale;

@Mixin(value = GemTypeFunction.class, remap = false)
public abstract class GemTypeFunctionMixin {
    private static final String[] STANDARD_TYPES = {
        "normal", "fighting", "flying", "poison", "ground", "rock",
        "bug", "ghost", "steel", "fire", "water", "grass",
        "electric", "psychic", "ice", "dragon", "dark", "fairy"
    };

    @Inject(method = "getGem", at = @At("HEAD"), cancellable = true, remap = false)
    private void cobbleverse$resolveGemFromRegistry(
        RaidType type,
        Random random,
        CallbackInfoReturnable<ItemStack> cir
    ) {
        String typeName = type == RaidType.STELLAR
            ? STANDARD_TYPES[random.nextInt(STANDARD_TYPES.length)]
            : type.name().toLowerCase(Locale.ROOT);

        Item gem = Registries.ITEM.get(Identifier.of("cobblemon", typeName + "_gem"));
        cir.setReturnValue(gem.getDefaultStack());
    }
}
