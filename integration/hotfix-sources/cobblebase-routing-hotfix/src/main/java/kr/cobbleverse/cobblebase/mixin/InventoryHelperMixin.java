package kr.cobbleverse.cobblebase.mixin;

import kr.cobbleverse.cobblebase.routing.RoutingPolicy;
import net.minecraft.block.BlockState;
import net.minecraft.item.ItemStack;
import net.minecraft.util.math.BlockPos;
import net.minecraft.world.World;
import notlown.cobblebase.core.executors.InventoryHelper;
import notlown.cobblebase.core.executors.InventoryHelper.GathererContainerCandidate;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

import java.util.List;
import java.util.Set;

@Mixin(value = InventoryHelper.class, remap = false)
public abstract class InventoryHelperMixin {
    @Unique
    private static final ThreadLocal<World> COBBLEVERSE_ROUTING_WORLD = new ThreadLocal<>();

    @Inject(method = "findGathererContainer", at = @At("HEAD"), remap = false)
    private void cobbleverse$captureWorld(
        World world,
        BlockPos origin,
        BlockPos pokemonPos,
        ItemStack stack,
        Set<? extends BlockPos> excluded,
        CallbackInfoReturnable<BlockPos> cir
    ) {
        COBBLEVERSE_ROUTING_WORLD.set(world);
    }

    @Inject(method = "findGathererContainer", at = @At("RETURN"), remap = false)
    private void cobbleverse$clearWorld(
        World world,
        BlockPos origin,
        BlockPos pokemonPos,
        ItemStack stack,
        Set<? extends BlockPos> excluded,
        CallbackInfoReturnable<BlockPos> cir
    ) {
        COBBLEVERSE_ROUTING_WORLD.remove();
    }

    @Inject(
        method = "selectGathererCandidate$cobblebase_common",
        at = @At("HEAD"),
        cancellable = true,
        remap = false
    )
    private void cobbleverse$selectNearbyAccessibleContainer(
        List<GathererContainerCandidate> candidates,
        String matchingCategory,
        String fallback,
        CallbackInfoReturnable<BlockPos> cir
    ) {
        List<CandidateAdapter> adapted = candidates.stream().map(CandidateAdapter::new).toList();
        World world = COBBLEVERSE_ROUTING_WORLD.get();

        BlockPos selected = RoutingPolicy.select(
                adapted,
                matchingCategory,
                fallback,
                candidate -> world == null || cobbleverse$hasOpenApproach(world, candidate.delegate().getPos())
            )
            .map(candidate -> candidate.delegate().getPos())
            .orElse(null);

        cir.setReturnValue(selected);
    }

    @Unique
    private boolean cobbleverse$hasOpenApproach(World world, BlockPos containerPos) {
        InventoryHelper helper = (InventoryHelper) (Object) this;
        for (BlockPos base : helper.gathererApproachCandidates(world, containerPos)) {
            if (cobbleverse$hasTwoBlockClearance(world, base)
                || cobbleverse$hasTwoBlockClearance(world, base.up())
                || cobbleverse$hasTwoBlockClearance(world, base.down())) {
                return true;
            }
        }
        return false;
    }

    @Unique
    private static boolean cobbleverse$hasTwoBlockClearance(World world, BlockPos feet) {
        BlockState feetState = world.getBlockState(feet);
        BlockPos head = feet.up();
        BlockState headState = world.getBlockState(head);
        return feetState.getCollisionShape(world, feet).isEmpty()
            && headState.getCollisionShape(world, head).isEmpty();
    }

    @Unique
    private record CandidateAdapter(GathererContainerCandidate delegate) implements RoutingPolicy.Candidate {
        @Override
        public String category() {
            return delegate.getCategory();
        }

        @Override
        public boolean hasExactStack() {
            return delegate.getHasExactStack();
        }

        @Override
        public int capacity() {
            return delegate.getCapacity();
        }

        @Override
        public boolean completelyEmpty() {
            return delegate.getCompletelyEmpty();
        }

        @Override
        public double distanceSquared() {
            return delegate.getDistanceSquared();
        }
    }
}
