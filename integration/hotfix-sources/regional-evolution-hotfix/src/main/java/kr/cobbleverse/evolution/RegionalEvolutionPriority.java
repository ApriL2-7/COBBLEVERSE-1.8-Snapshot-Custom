package kr.cobbleverse.evolution;

import java.util.Objects;

public final class RegionalEvolutionPriority {
    private RegionalEvolutionPriority() {
    }

    public interface Candidate {
        Object variantKey();
        Object contextKey();
        boolean hasPositiveBiomeCondition();
        boolean requirementsPass();
    }

    public static boolean shouldSuppressGeneral(Candidate current, Iterable<? extends Candidate> candidates) {
        if (current.hasPositiveBiomeCondition()) {
            return false;
        }

        for (Candidate alternative : candidates) {
            if (alternative == current
                || !Objects.equals(current.variantKey(), alternative.variantKey())
                || !Objects.equals(current.contextKey(), alternative.contextKey())
                || !alternative.hasPositiveBiomeCondition()) {
                continue;
            }
            if (alternative.requirementsPass()) {
                return true;
            }
        }
        return false;
    }
}
