Shader "Hidden/Back-face Depth Camera"
{
    CGINCLUDE
    #include "UnityCG.cginc"

    struct Input
    {
        float4 vertex : POSITION;
        float4 uv : TEXCOORD0;
    };

    struct Varyings
    {
        float4 vertex : SV_POSITION;
        float depth : TEXCOORD0;
    };

    Varyings vertex(in Input input)
    {
        Varyings output;

        output.vertex = UnityObjectToClipPos(input.vertex);
        output.depth = -UnityObjectToViewPos(input.vertex).z * _ProjectionParams.w;

        return output;
    }

    float4 fragment(in Varyings input) : SV_Target
    {
        return input.depth;
    }
    ENDCG

    SubShader
    {
        Pass
        {
            Tags { "RenderType"="Opaque" }
            Cull front

            CGPROGRAM
            #pragma vertex vertex
            #pragma fragment fragment
            ENDCG
        }
    }
}
