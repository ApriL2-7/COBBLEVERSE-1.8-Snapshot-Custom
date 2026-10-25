package kr.cobbleverse.runtime.mixin;

import com.pokemon.battlepositions.battle.PositionBlockFinder;
import net.minecraft.server.world.ServerWorld;
import net.minecraft.util.math.BlockPos;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(value = PositionBlockFinder.class, remap = false)
public abstract class PositionBlockFinderMixin {
    @Inject(method = "findPositionBlocks", at = @At("RETURN"), cancellable = true, remap = false)
    private static void cobbleverse$inferMissingTrainerStand(
        ServerWorld world,
        BlockPos origin,
        CallbackInfoReturnable<PositionBlockFinder.PositionBlockSet> cir
    ) {
        PositionBlockFinder.PositionBlockSet positions = cir.getReturnValue();
        if (positions == null
            || positions.trainerStandPos != null
            || positions.trainerPokemonPos == null
            || positions.playerPokemonPos == null
            || positions.playerStandPos == null) {
            return;
        }

        int offsetX = positions.playerStandPos.getX() - positions.playerPokemonPos.getX();
        int offsetY = positions.playerStandPos.getY() - positions.playerPokemonPos.getY();
        int offsetZ = positions.playerStandPos.getZ() - positions.playerPokemonPos.getZ();
        BlockPos inferredTrainerStand = positions.trainerPokemonPos.add(-offsetX, -offsetY, -offsetZ);

        cir.setReturnValue(new PositionBlockFinder.PositionBlockSet(
            positions.trainerPokemonPos,
            positions.playerPokemonPos,
            inferredTrainerStand,
            positions.playerStandPos
        ));
    }
}
