/* BSD 3-CLAUSE LICENSE
Copyright (c) 2026, Error.mdl

All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice,
      this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice,
      this list of conditions and the following disclaimer in the documentation
      and/or other materials provided with the distribution.
    * Neither the name of the copyright holder nor the names of its contributors
      may be used to endorse or promote products derived from this software
      without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

Shader "Basis/Base PBR"
{
    Properties
    {
        [MainTexture]           _BaseMap          ("Albedo Texture",               2D     ) = "white"   {}
        [MainColor]             _BaseColor        ("Albedo Color",                 Color  ) = (1,1,1,1)
        [NoScaleOffset][Normal] _BumpMap          ("Normal Map",                   2D     ) = "bump"    {}
        [NoScaleOffset]         _MetallicGlossMap ("Metallic (R), Smoothness (A)", 2D     ) = "white"   {}
                                _NormMetSmScale   ("Normal, Metallic, Smoothness", Vector ) = (1, 0, 0.5, 0)
        [ToggleUI]              _Emission         ("Enable Emission",              float  ) = 0
        [NoScaleOffset]         _EmissionMap      ("Emission Map",                 2D     ) = "black"   {}
        [HDR]                   _EmissionColor    ("Emission Color",               Color  ) = (1,1,1,1)

        [Toggle(_SPECULAR_SETUP)]
                                _Specular         ("Specular Workflow",            float  ) = 0
        [Enum(Metallic Alpha,0,Albedo Alpha,1)]
                                _SmoothnessTextureChannel ("Smoothness Source",    float  ) = 0
    }
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "UniversalMaterialType" = "Lit"
            "IgnoreProjector" = "True"
        }
        LOD 100

        HLSLINCLUDE

            // Allow PC to use relaxed precision floats (half will be defined as min16float instead of float)
            #define UNITY_UNIFIED_SHADER_PRECISION_MODEL 1

            // Uncomment to use DXC with D3D12, but this will make the shader unable to compile for D3D11!
            //#define USE_DXC_D3D12_AND_BREAK_D3D11

            // With depth-priming on D3D, NVidia experiences slight inconsistencies between 
            // the depth calculated in the forward pass and depth prepass if a different 
            // per-material cbuffer is declared in each. This results in the object appearing 
            // to z-fight with the background. Therefore, include the same UnityPerMaterial in
            // every pass that uses any material property

            #define PER_MATERIAL_CBUFFER  \
                float4 _BaseMap_ST;       \
                float4 _BaseColor;        \
                float4 _NormMetSmScale;   \
                float4 _EmissionColor;    \
                float  _Emission; \
                float  _Specular; \
                float  _SmoothnessTextureChannel;

         ENDHLSL

        Pass
        {
            Name "Forward"
            Tags {"Lightmode" = "UniversalForward"}
            
            HLSLPROGRAM
            #pragma target 5.0

            #pragma vertex Vert
            #pragma fragment Frag

            // Specular has to be a keyword to use the unmodified UniversalFragmentPBR function
            #pragma shader_feature _SPECULAR_SETUP

            // SRP's dont automatically define symbols for the pass like UNITY_PASS_FORWARDBASE etc. 
            // However, the shadergraph added its own system that has to manually be declared like this.
            #include "Packages/com.unity.render-pipelines.universal/Editor/ShaderGraph/Includes/ShaderPass.hlsl"
            #define SHADERPASS SHADERPASS_FORWARD

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // Enable the DXC shader compiler whenever possible. 
            #include_with_pragmas "DXCSupport.hlsl"

            // Fix OOB instance property cbuffer index with DXC and android
            #if defined(NEEDS_FORCE_MAX_INSTANCE_COUNT)
            #pragma instancing_options maxcount:128 forcemaxcount:128
            #endif

            ///----------------------------
            /// Default Lit Variants Config
            ///----------------------------
            
            #if defined(SHADER_API_MOBILE) // Android/iOS
                #define R_ADDITIONAL_LIGHTS_FRAG    0 
                #define R_ADDITIONAL_LIGHTS_VTX     2
                
                // Basis does not use F+ on mobile since Qualcomm's gpu 
                // architecture is archaic and dies when constants aren't
                // accessed at fixed addresses
                #define R_FORWARD_PLUS              0 
                #define R_SCREEN_SPACE_GI           0
                #define R_LIGHTMAP_BICUBIC          0
            #else // PC
                // Not sure if it's safe to just force on additional lights?
                #define R_ADDITIONAL_LIGHTS_FRAG    1 
                #define R_ADDITIONAL_LIGHTS_VTX     0
                // Basis is always F+ on PC
                #define R_FORWARD_PLUS              1
                #define R_SCREEN_SPACE_GI           0
                #define R_LIGHTMAP_BICUBIC          2
            #endif

            #define R_NORMALMAP                 2
            #define R_ADAPTIVE_PROBE_VOLUMES    1   // 1 - multi-compile L1 and L2, 2 - L1 forced on, 3 - l1+l2 forced on. 
            #define R_LIGHTMAP_VARIANTS         1
            #define R_LIGHT_LAYERS              0  // Uses MRT, bad!
            #define R_USE_RENDERING_LAYERS      0  // Uses MRT, bad!
            #define R_DOTS_INSTANCING           1  // Needs to be on for gpu drawers!!!!!
            #define R_DECAL_BUFFER              0  // Decal buffer is terrible, this shader does not implement it
            
            ///----------------------------
            /// End Default Lit Variants Config
            ///----------------------------
            
            #include_with_pragmas "DefaultLitVariants.hlsl"

            // instancing_options are ignored inside files with include_with_pragmas defined!
            #if R_USE_RENDER_LAYERS > 0
            #pragma instancing_options renderinglayer
            #endif

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
    
            struct VertexData
            {
                float3 positionOS  : POSITION;
                float3 normalOS    : NORMAL;
                float4 tangentOS   : TANGENT;
                float2 uv0         : TEXCOORD0;
                
                #if defined(LIGHTMAP_ON)
                float2 uv1       : TEXCOORD1;
                #endif
                
                #if defined(DYNAMICLIGHTMAP_ON)
                float2 uv2       : TEXCOORD2;
                #endif
                
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
    
            // The compiler does _not_ optimize the vertex output/fragment input interpolators! (the driver should, but don't rely on it)
            // It's up to us to pack them tightly as possible!
            struct Interpolators
            {
                float4      positionCS         : SV_POSITION;
                #if defined(LIGHTMAP_ON) || defined(DYNAMICLIGHTMAP_ON)
                    float4 lightmapUVs         : LMUV;
                #endif

                min16float4 normXYZ_fog        : NORMAL;
                min16float4 tanXYZ_btSign      : TANGENT;

                #if defined(ADDITIONAL_LIGHTS_VERTEX)
                    min16float4 vertexLighting : VTXLIGHT;
                #endif

                float3      positionWS         : WPOS;
                float2      uv0                : TEXCOORD0;

                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };
            
            #define WORLD_POS(i)      i.positionWS.xyz
            #define UV0(i)            i.uv0
            #define WORLD_NORMAL(i)   i.normXYZ_fog.xyz
            #define WORLD_TANGENT(i)  i.tanXYZ_btSign.xyz
            #define BITANGENT_SIGN(i) i.tanXYZ_btSign.w
            #define FOG_FACTOR(i)     i.normXYZ_fog.w
            #define STATIC_LM_UV(i)   i.lightmapUVs.xy
            #define DYNAMIC_LM_UV(i)  i.lightmapUVs.zw
            #define VTX_LIGHTING(i)   i.vertexLighting.xyz
    
            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BumpMap);
            TEXTURE2D(_MetallicGlossMap);
            TEXTURE2D(_EmissionMap);

            CBUFFER_START(UnityPerMaterial)
            PER_MATERIAL_CBUFFER
            CBUFFER_END

            Interpolators Vert(VertexData v)
            {
                Interpolators ipl = (Interpolators)0;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, ipl);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(ipl);
                
                WORLD_POS(ipl) = TransformObjectToWorld(v.positionOS);
                ipl.positionCS = TransformWorldToHClip(WORLD_POS(ipl));
                
                WORLD_NORMAL(ipl) = (min16float3)TransformObjectToWorldNormal(v.normalOS);
                WORLD_TANGENT(ipl) = (min16float3)TransformObjectToWorldDir(v.tangentOS.xyz);
                BITANGENT_SIGN(ipl) = (min16float)(v.tangentOS.w * GetOddNegativeScale());
                UV0(ipl) = TRANSFORM_TEX(v.uv0, _BaseMap);
                FOG_FACTOR(ipl) = (min16float)ComputeFogFactor(ipl.positionCS.z);
                
                #if defined(LIGHTMAP_ON)
                    OUTPUT_LIGHTMAP_UV(v.uv1, unity_LightmapST, STATIC_LM_UV(ipl));
                #endif
                
                #if defined(DYNAMICLIGHTMAP_ON)
                    DYNAMIC_LM_UV(ipl) = v.uv2 * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
                #endif
                
                #if defined(ADDITIONAL_LIGHTS_VERTEX)
                    VTX_LIGHTING(ipl) = (min16float3)VertexLighting(WORLD_POS(ipl), WORLD_NORMAL(ipl));
                #endif
                
                return ipl;
            }

            struct FragmentOutput
            {
                float4 color : SV_Target0;
            };

            FragmentOutput Frag(Interpolators i)
            {
                FragmentOutput fragOut = (FragmentOutput)0;
                
                UNITY_SETUP_INSTANCE_ID(i);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                
                half4 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, UV0(i));
                albedo *= _BaseColor;
                
                half4 metallicGlossMap = SAMPLE_TEXTURE2D(_MetallicGlossMap, sampler_BaseMap, UV0(i));
                half metallic = metallicGlossMap.r * _NormMetSmScale.y;
                half smoothness = _SmoothnessTextureChannel == 0 ? metallicGlossMap.a : albedo.a;
                smoothness *= _NormMetSmScale.z;
                
                half4 normalMap = SAMPLE_TEXTURE2D(_BumpMap, sampler_BaseMap, UV0(i));
                half3 normalTS = UnpackNormalScale(normalMap, _NormMetSmScale.x);
                
                half3 emission = (half3)0;
                if (_Emission != 0)
                {
                    emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_BaseMap, UV0(i)).rgb;
                    emission *= _EmissionColor.rgb;
                }
                
                ///---------------------------
                /// Fragment data
                ///---------------------------
                FragData fragData = GetDefaultFragData();

                fragData.positionCS        = i.positionCS;
                fragData.positionWS        = WORLD_POS(i);
                fragData.vtxNormalWS       = WORLD_NORMAL(i);
                fragData.vtxTangentWS      = WORLD_TANGENT(i);
                fragData.BitangentSign     = BITANGENT_SIGN(i);
                fragData.uv                = UV0(i);
                #if defined(LIGHTMAP_ON)
                fragData.lightmapUV        = STATIC_LM_UV(i);
                #endif
                #if defined(DYNAMICLIGHTMAP_ON)
                fragData.dynamicLightmapUV = DYNAMIC_LM_UV(i);
                #endif
                #if defined(ADDITIONAL_LIGHTS_VERTEX)
                fragData.vertexLight       = VTX_LIGHTING(i);
                #endif
                fragData.fogFactor         = FOG_FACTOR(i);
                
                ///---------------------------
                /// Populate URP input data struct
                ///---------------------------
                
                InputData urpInputData;
                InitializeInputData(fragData, normalTS, /*out*/ urpInputData);
                SETUP_DEBUG_TEXTURE_DATA(inputData, UNDO_TRANSFORM_TEX(UV0(i), _BaseMap));
                InitializeBakedGIData(fragData, /*inout*/ urpInputData);
                
                ///---------------------------
                /// Populate URP surface data struct
                ///---------------------------
                
                SurfaceData surfData = GetDefaultSurfaceData();
                
                surfData.albedo              = albedo;
                surfData.specular            = _Specular ? metallicGlossMap.rgb : (half3)0;
                surfData.metallic            = metallic;
                surfData.smoothness          = smoothness;
                surfData.normalTS            = normalTS;
                surfData.emission            = emission;
                surfData.occlusion           = 1; // Occlusion texture, we don't have this right now
                surfData.alpha               = 1;
                surfData.clearCoatMask       = 0;
                surfData.clearCoatSmoothness = 0;
                
               
                // Call URP Lit's shading function
                fragOut.color = UniversalFragmentPBR(urpInputData, surfData);

                // Mix fog
                fragOut.color.rgb = MixFog(fragOut.color.rgb, FOG_FACTOR(i));

                // Don't output alpha if opaque
                fragOut.color.a = OutputAlpha(fragOut.color.a, IsSurfaceTypeTransparent(kSurfaceTypeOpaque)); // replace with kSurfaceTypeTransparent if transparent
    
                return fragOut;
            }

            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags {"Lightmode" = "DepthOnly"}

            HLSLPROGRAM
                
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/Editor/ShaderGraph/Includes/ShaderPass.hlsl"
            #define SHADERPASS SHADERPASS_DEPTHONLY

            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // Enable the DXC shader compiler whenever possible. 
            #include_with_pragmas "DXCSupport.hlsl"

            // Fix OOB instance property cbuffer index with DXC and android
            #if defined(NEEDS_FORCE_MAX_INSTANCE_COUNT)
            #pragma instancing_options maxcount:128 forcemaxcount:128
            #endif

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct VertexData
            {
                float3 positionOS  : POSITION;
    
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Interpolators
            {
                float4 positionCS  : SV_POSITION;
    
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Interpolators vert(VertexData v)
            {
                Interpolators ipl;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, ipl);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(ipl);
        
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                ipl.positionCS = TransformWorldToHClip(positionWS);

                return ipl;
            }

            struct DepthOutput
            {
                
            };

            // Make function void to give a hint to the driver that it can skip fragment shader execution entirely
            // Change to output SV_Depth/SV_DepthLessEqual if modifying per-pixel depth in forward pass
            void frag(Interpolators i)
            {
                // UNITY_SETUP_INSTANCE_ID(i);
                // UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                
                // clip for alphatest here, also
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags {"Lightmode" = "DepthNormals"}

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/Editor/ShaderGraph/Includes/ShaderPass.hlsl"
            #define SHADERPASS SHADERPASS_DEPTHNORMALS

            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // Enable the DXC shader compiler whenever possible. 
            #include_with_pragmas "DXCSupport.hlsl"

            // Fix OOB instance property cbuffer index with DXC and android
            #if defined(NEEDS_FORCE_MAX_INSTANCE_COUNT)
            #pragma instancing_options maxcount:128 forcemaxcount:128
            #endif

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct VertexData
            {
                float3 positionOS : POSITION;
                min16float3 normalOS   : NORMAL;
                min16float4 tangentOS  : TANGENT;
                min16float2 uv0        : TEXCOORD0;
                
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Interpolators
            {
                float4 positionCS            : SV_POSITION;
                min16float3 normalWS         : NORMAL;
                min16float4 tangentWS_btSign : TANGENT;
                float2 uv0                   : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID // Instance ID is necessary for DOTS and the GPU Drawer, don't forget this!
                UNITY_VERTEX_OUTPUT_STEREO
            };

            CBUFFER_START(UnityPerMaterial)
            PER_MATERIAL_CBUFFER
            CBUFFER_END
            
            TEXTURE2D(_BumpMap);
            SAMPLER(sampler_BumpMap);

            Interpolators vert(VertexData v)
            {
                Interpolators ipl;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, ipl);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(ipl);

                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                ipl.positionCS = TransformWorldToHClip(positionWS);
                ipl.normalWS = TransformObjectToWorldNormal(v.normalOS, false);
                ipl.tangentWS_btSign.xyz = TransformObjectToWorldDir(v.tangentOS.xyz, false);
                ipl.tangentWS_btSign.w = (min16float)(v.tangentOS.w * GetOddNegativeScale());
                ipl.uv0 = TRANSFORM_TEX(v.uv0, _BaseMap);

                return ipl;
            }

            half4 frag(Interpolators i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                
                min16float3 normalWS    = i.normalWS.xyz;
                min16float3 tangentWS   = i.tangentWS_btSign.xyz;
                min16float bitangentSign = i.tangentWS_btSign.w;
                min16float3 bitangentWS = cross(normalWS, tangentWS) * bitangentSign;
                
                min16float3x3 tangentToWorld = min16float3x3(
                    tangentWS.x, bitangentWS.x, normalWS.x,
                    tangentWS.y, bitangentWS.y, normalWS.y,
                    tangentWS.z, bitangentWS.z, normalWS.z
                );
                
                min16float3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, i.uv0), _NormMetSmScale.x);
                
                min16float3 outNormalWS = normalize(mul(tangentToWorld, normalTS));
                
                #if defined(_GBUFFER_NORMALS_OCT)
                    
                    float2 octNormalWS = PackNormalOctQuadEncode(normalWS);           // values between [-1, +1], must use fp32 on some platforms.
                    float2 remappedOctNormalWS = saturate(octNormalWS * 0.5 + 0.5);   // values between [ 0,  1]
                    half3 packedNormalWS = PackFloat2To888(remappedOctNormalWS);      // values between [ 0,  1]
                    outNormalWS = half4(packedNormalWS, 0.0);
                #endif
                
                return half4(outNormalWS, 0.0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "Shadowcaster"
            Tags {"Lightmode" = "Shadowcaster"}

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/Editor/ShaderGraph/Includes/ShaderPass.hlsl"
            #define SHADERPASS SHADERPASS_SHADOWCASTER

            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // Enable the DXC shader compiler whenever possible. 
            #include_with_pragmas "DXCSupport.hlsl"

            // Fix OOB instance property cbuffer index with DXC and android
            #if defined(NEEDS_FORCE_MAX_INSTANCE_COUNT)
            #pragma instancing_options maxcount:128 forcemaxcount:128
            #endif

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            struct VertexData
            {
                float3 positionOS : POSITION;
                half3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Interpolators
            {
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            float3 _LightDirection;
            float3 _LightPosition;


            // http://the-witness.net/news/2013/09/shadow-mapping-summary-part-1/
            float3 BetterApplyShadowBias(float3 positionWS, float3 normalWS, float3 lightDirection)
            {
                half NoL = saturate(dot(normalWS, lightDirection));
                half offsetNormal = sqrt(1 - NoL * NoL); 
                half offsetLight = min(2.0, offsetNormal / NoL);
                
                positionWS.xyz -= offsetLight * lightDirection.xyz * 0.01; 
                return positionWS.xyz;
            }
    
            Interpolators vert(VertexData v)
            {
                Interpolators ipl;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, ipl);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(ipl);
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS, true);
#if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 wLightDir = normalize(_LightPosition - positionWS);
#else
                float3 wLightDir = _LightDirection;
#endif
                ipl.positionCS = TransformWorldToHClip(BetterApplyShadowBias(positionWS, normalWS, wLightDir));
                return ipl;
            }

            void frag(Interpolators i)
            {
                UNITY_SETUP_INSTANCE_ID(i);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
            }
            ENDHLSL
        }

        Pass
        {
            Name "Meta"
            Tags {"Lightmode" = "Meta"}

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/Editor/ShaderGraph/Includes/ShaderPass.hlsl"
            #define SHADERPASS SHADERPASS_META

            #pragma shader_feature EDITOR_VISUALIZATION

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // Enable the DXC shader compiler whenever possible. 
            #include_with_pragmas "DXCSupport.hlsl"

            // Fix OOB instance property cbuffer index with DXC and android
            #if defined(NEEDS_FORCE_MAX_INSTANCE_COUNT)
            #pragma instancing_options maxcount:128 forcemaxcount:128
            #endif

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/MetaInput.hlsl"

            struct VertexData
            {
                float3 positionOS : POSITION;
                float2 uv0 : TEXCOORD0;
                float2 uv1 : TEXCOORD1;
                float2 uv2 : TEXCOORD2;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Interpolators
            {
                float4 positionCS : SV_POSITION;
                float2 uv0        : TEXCOORD0;
                #if defined(EDITOR_VISUALIZATION)
                float2 VizUV        : TEXCOORD1;
                float4 LightCoord   : TEXCOORD2;
                #endif
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            TEXTURE2D(_EmissionMap);

            CBUFFER_START(UnityPerMaterial)
            PER_MATERIAL_CBUFFER
            CBUFFER_END

            Interpolators vert(VertexData v)
            {
                Interpolators ipl;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, ipl);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(ipl);
                
                ipl.positionCS = UnityMetaVertexPosition(v.positionOS.xyz, v.uv1, v.uv2);
                ipl.uv0 = TRANSFORM_TEX(v.uv0, _BaseMap);
                
                #if defined(EDITOR_VISUALIZATION)
                    UnityEditorVizData(v.positionOS.xyz, v.uv0, v.uv1, v.uv2, o.VizUV, o.LightCoord);
                #endif
                return ipl;
            }

            half4 frag(Interpolators i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                
                half4 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv0);
                MetaInput metaInput = (MetaInput)0; 
                metaInput.Albedo = albedo.rgb;
                if (_Emission != 0)
                {
                    metaInput.Emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_BaseMap, i.uv0).rgb * _EmissionColor.rgb;
                }
                #ifdef EDITOR_VISUALIZATION
                    metaInput.VizUV = i.VizUV.xy;
                    metaInput.LightCoord = i.LightCoord;
                #endif

                return MetaFragment(metaInput);
            }
            ENDHLSL
        }

        Pass
        {
            Name "MotionVectors"
            Tags { "LightMode" = "MotionVectors" }
            ColorMask RG

            HLSLPROGRAM

            #include "Packages/com.unity.render-pipelines.universal/Editor/ShaderGraph/Includes/ShaderPass.hlsl"
            #define SHADERPASS SHADERPASS_MOTION_VECTORS

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            // Enable the DXC shader compiler whenever possible. 
            #include_with_pragmas "DXCSupport.hlsl"

            // Fix OOB instance property cbuffer index with DXC and android
            #if defined(NEEDS_FORCE_MAX_INSTANCE_COUNT)
            #pragma instancing_options maxcount:128 forcemaxcount:128
            #endif

            #pragma shader_feature_local_vertex _ADD_PRECOMPUTED_VELOCITY

            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ObjectMotionVectors.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "XRMotionVectors"
            Tags { "LightMode" = "XRMotionVectors" }

            // Stencil write for obj motion pixels
            Stencil
            {
                WriteMask 1
                Ref 1
                Comp Always
                Pass Replace
            }

            HLSLPROGRAM

            #include "Packages/com.unity.render-pipelines.universal/Editor/ShaderGraph/Includes/ShaderPass.hlsl"
            #define SHADERPASS SHADERPASS_XR_MOTION_VECTORS

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            // Enable the DXC shader compiler whenever possible. 
            #include_with_pragmas "DXCSupport.hlsl"

            // Fix OOB instance property cbuffer index with DXC and android
            #if defined(NEEDS_FORCE_MAX_INSTANCE_COUNT)
            #pragma instancing_options maxcount:128 forcemaxcount:128
            #endif

            #pragma shader_feature_local_vertex _ADD_PRECOMPUTED_VELOCITY
            #define APPLICATION_SPACE_WARP_MOTION 1

            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ObjectMotionVectors.hlsl"
            ENDHLSL
        }
    }
}
