/**
 * Central registry of 30 official UPI application providers.
 * Real official Google Play Store listing CDN icons and official brand assets.
 */
export interface UpiProvider {
    id: string;
    name: string;
    shortName: string;
    packageName: string;
    iconUrl: string;
    brandColor: string;
    searchKeywords: string[];
    enabled: boolean;
    svgLogo: string;
}
export declare const UPI_PROVIDERS: UpiProvider[];
export declare function getUpiProviders(): UpiProvider[];
export declare function findUpiProviderByPackage(packageName?: string): UpiProvider | undefined;
export declare function findUpiProviderById(id?: string): UpiProvider | undefined;
//# sourceMappingURL=upi-providers.d.ts.map