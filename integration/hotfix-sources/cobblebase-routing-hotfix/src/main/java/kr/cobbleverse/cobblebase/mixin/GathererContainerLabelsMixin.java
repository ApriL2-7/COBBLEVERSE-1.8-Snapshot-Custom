package kr.cobbleverse.cobblebase.mixin;

import notlown.cobblebase.fabric.GathererContainerLabels;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.Constant;
import org.spongepowered.asm.mixin.injection.ModifyConstant;

@Mixin(value = GathererContainerLabels.class, remap = false)
public abstract class GathererContainerLabelsMixin {
    /**
     * Cobblebase normally places the label 1.1 blocks above the top of the
     * container. Keep its existing facing-aware horizontal offset, but lower
     * the text to the vertical centre of the chest's front face.
     */
    @ModifyConstant(
        method = "update",
        constant = @Constant(doubleValue = 1.1D),
        require = 1,
        remap = false
    )
    private double cobbleverse$placeLabelOnContainerFront(double original) {
        return 0.5D;
    }
}
