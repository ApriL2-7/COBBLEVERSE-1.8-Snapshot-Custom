package kr.cobbleverse.evolution.mixin;

import com.cobblemon.mod.common.api.pokemon.evolution.ContextEvolution;
import com.cobblemon.mod.common.api.pokemon.evolution.Evolution;
import com.cobblemon.mod.common.api.pokemon.requirement.Requirement;
import com.cobblemon.mod.common.pokemon.Pokemon;
import com.cobblemon.mod.common.pokemon.requirements.BiomeRequirement;
import kr.cobbleverse.evolution.RegionalEvolutionPriority;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

import java.util.ArrayList;
import java.util.List;

@Mixin(value = Evolution.class, remap = false)
public interface EvolutionMixin {
    @Inject(method = "test", at = @At("HEAD"), cancellable = true, remap = false)
    private void cobbleverse$preferMatchingRegionalEvolution(
        Pokemon pokemon,
        CallbackInfoReturnable<Boolean> cir
    ) {
        Evolution current = (Evolution) this;
        List<EvolutionAdapter> candidates = new ArrayList<>();
        EvolutionAdapter currentAdapter = null;

        for (Evolution evolution : pokemon.getLockedEvolutions()) {
            EvolutionAdapter adapter = new EvolutionAdapter(evolution, pokemon);
            candidates.add(adapter);
            if (evolution == current) {
                currentAdapter = adapter;
            }
        }

        if (currentAdapter != null
            && RegionalEvolutionPriority.shouldSuppressGeneral(currentAdapter, candidates)) {
            cir.setReturnValue(false);
        }
    }

    @Unique
    private static boolean cobbleverse$hasPositiveBiomeCondition(Evolution evolution) {
        for (Requirement requirement : evolution.getRequirements()) {
            if (requirement instanceof BiomeRequirement biome
                && biome.getBiomeCondition() != null) {
                return true;
            }
        }
        return false;
    }

    @Unique
    private static boolean cobbleverse$requirementsPass(Evolution evolution, Pokemon pokemon) {
        for (Requirement requirement : evolution.getRequirements()) {
            if (!requirement.check(pokemon)) {
                return false;
            }
        }
        return true;
    }

    @Unique
    record EvolutionAdapter(Evolution evolution, Pokemon pokemon)
        implements RegionalEvolutionPriority.Candidate {

        @Override
        public Object variantKey() {
            return evolution.getClass();
        }

        @Override
        public Object contextKey() {
            return evolution instanceof ContextEvolution<?, ?> contextEvolution
                ? contextEvolution.getRequiredContext()
                : null;
        }

        @Override
        public boolean hasPositiveBiomeCondition() {
            return cobbleverse$hasPositiveBiomeCondition(evolution);
        }

        @Override
        public boolean requirementsPass() {
            return cobbleverse$requirementsPass(evolution, pokemon);
        }
    }
}
