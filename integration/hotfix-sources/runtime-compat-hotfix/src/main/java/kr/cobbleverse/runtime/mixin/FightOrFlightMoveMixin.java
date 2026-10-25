package kr.cobbleverse.runtime.mixin;

import com.cobblemon.mod.common.api.moves.Move;
import com.cobblemon.mod.common.api.moves.MoveSet;
import com.cobblemon.mod.common.entity.pokemon.PokemonEntity;
import me.rufia.fightorflight.utils.PokemonUtils;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(value = PokemonUtils.class, remap = false)
public abstract class FightOrFlightMoveMixin {
    @Inject(method = "findMove", at = @At("HEAD"), cancellable = true, remap = false)
    private static void cobbleverse$findConfiguredCurrentMove(
        PokemonEntity entity,
        String moveName,
        CallbackInfoReturnable<Move> cir
    ) {
        if (entity == null || moveName == null || moveName.isBlank()) {
            return;
        }

        MoveSet moveSet = entity.getPokemon().getMoveSet();
        for (int slot = 0; slot < 4; slot++) {
            Move move = moveSet.get(slot);
            if (move != null && move.getName().equalsIgnoreCase(moveName)) {
                cir.setReturnValue(move);
                return;
            }
        }
    }
}
