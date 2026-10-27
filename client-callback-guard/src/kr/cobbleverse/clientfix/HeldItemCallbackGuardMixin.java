package kr.cobbleverse.clientfix;

import com.cobblemon.mod.common.api.events.pokemon.HeldItemEvent;
import com.cobblemon.mod.common.pokemon.Pokemon;
import com.cobblemon.mod.common.util.DistributionUtilsKt;
import kotlin.Unit;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

/** Only skip server-script listeners; other held-item listeners and synchronization still run. */
@Mixin(targets = "com.cobblemon.mod.common.events.CallbackHandler", remap = false)
public abstract class HeldItemCallbackGuardMixin {
    @Unique
    private static boolean missingServerContext(Pokemon pokemon) {
        return pokemon.isClient$common() || DistributionUtilsKt.server() == null;
    }

    @Inject(method = {
        "setup$lambda$44(Lcom/cobblemon/mod/common/api/events/pokemon/HeldItemEvent$Pre;)Lkotlin/Unit;",
        "setup$lambda$46(Lcom/cobblemon/mod/common/api/events/pokemon/HeldItemEvent$Pre;)Lkotlin/Unit;"
    }, at = @At("HEAD"), cancellable = true, remap = false)
    private static void guardPre(HeldItemEvent.Pre event, CallbackInfoReturnable<Unit> cir) {
        if (missingServerContext(event.getPokemon())) cir.setReturnValue(Unit.INSTANCE);
    }

    @Inject(method = {
        "setup$lambda$45(Lcom/cobblemon/mod/common/api/events/pokemon/HeldItemEvent$Post;)Lkotlin/Unit;",
        "setup$lambda$47(Lcom/cobblemon/mod/common/api/events/pokemon/HeldItemEvent$Post;)Lkotlin/Unit;"
    }, at = @At("HEAD"), cancellable = true, remap = false)
    private static void guardPost(HeldItemEvent.Post event, CallbackInfoReturnable<Unit> cir) {
        if (missingServerContext(event.getPokemon())) cir.setReturnValue(Unit.INSTANCE);
    }
}
