Shader "Hidden/Screen-space Ray Marching"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }

    CGINCLUDE
    #include "UnityCG.cginc"
    #include "UnityPBSLighting.cginc"
    #include "UnityStandardBRDF.cginc"
    #include "UnityStandardUtils.cginc"

    struct Input
    {
        float4 vertex : POSITION;
        float2 uv : TEXCOORD0;
    };

    struct Varyings
    {
        float4 vertex : SV_POSITION;
        float2 uv : TEXCOORD0;
    };

    struct Ray
    {
        float3 origin;
        float3 direction;
    };

    struct Segment
    {
        float3 start;
        float3 end;

        float3 direction;
    };

    struct Result
    {
        bool isHit;

        float2 uv;
        float3 position;

        int iterationCount;
    };

    sampler2D _MainTex;

    sampler2D _CameraDepthTexture;
    sampler2D _CameraBackFaceDepthTexture;
    sampler2D _CameraReflectionsTexture;

    sampler2D _CameraGBufferTexture0; // albedo = g[0].rgb
    sampler2D _CameraGBufferTexture1; // roughness = g[1].a
    sampler2D _CameraGBufferTexture2; // normal.xyz 2. * g[2].rgb - 1.

    int _MaximumIterationCount;
    float _MaximumMarchDistance;

    float4 _MainTex_TexelSize;
    float4 _CameraDepthTexture_TexelSize;
    float4 _CameraBackFaceDepthTexture_TexelSize;

    float4x4 _ViewMatrix;
    float4x4 _InverseViewMatrix;
    float4x4 _ProjectionMatrix;
    float4x4 _ScreenSpaceProjectionMatrix;

    Varyings vertex(in Input input)
    {
        Varyings output;

        output.vertex = UnityObjectToClipPos(input.vertex);
        output.uv = input.uv;

    #if UNITY_UV_STARTS_AT_TOP
        if (_MainTex_TexelSize.y < 0)
            output.uv.y = 1. - input.uv.y;
    #endif

        return output;
    }

    float3 getViewSpacePosition(in float2 uv)
    {
        float depth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));
        return float3((2. * uv - 1.) / float2(_ProjectionMatrix[0][0], _ProjectionMatrix[1][1]), -1.) * depth;
    }

    float getSquaredDistance(in float2 first, in float2 second)
    {
        first -= second;
        return dot(first, first);
    }

    float4 projectToScreenSpace(in float3 position)
    {
        return float4(
            _ScreenSpaceProjectionMatrix[0][0] * position.x + _ScreenSpaceProjectionMatrix[0][2] * position.z,
            _ScreenSpaceProjectionMatrix[1][1] * position.y + _ScreenSpaceProjectionMatrix[1][2] * position.z,
            _ScreenSpaceProjectionMatrix[2][2] * position.z + _ScreenSpaceProjectionMatrix[2][3],
            _ScreenSpaceProjectionMatrix[3][2] * position.z
        );
    }

    bool query(in float2 z, float2 uv)
    {
        float2 depths = float2(
            -LinearEyeDepth(tex2Dlod(_CameraDepthTexture, float4(uv, 0., 0.)).r),
            tex2Dlod(_CameraBackFaceDepthTexture, float4(uv, 0., 0.)).r * -_ProjectionParams.z
        );

        return step(z.y, depths.x) * step(depths.y - .0125, z.x);
    }

    /* Heavily adapted from McGuire and Mara's original implementation
     * http://casual-effects.blogspot.com/2014/08/screen-space-ray-tracing.html */
    Result march(in Ray ray)
    {
        Result result;

        result.isHit = false;

        result.uv = 0.;
        result.position = 0.;

        result.iterationCount = 0;

        Segment segment;

        segment.start = ray.origin;

        float end = ray.origin.z + ray.direction.z * _MaximumMarchDistance;
        float magnitude = _MaximumMarchDistance;

        if (end > -_ProjectionParams.y)
            magnitude = (-_ProjectionParams.y - ray.origin.z) / ray.direction.z;

        segment.end = ray.origin + ray.direction * magnitude;

        float4 r = projectToScreenSpace(segment.start);
        float4 q = projectToScreenSpace(segment.end);

        const float2 homogenizers = 1. / float2(r.w, q.w);

        segment.start *= homogenizers.x;
        segment.end *= homogenizers.y;

        float4 endPoints = float4(r.xy, q.xy) * homogenizers.xxyy;
        endPoints.zw += step(getSquaredDistance(endPoints.xy, endPoints.zw), .0001) * max(_MainTex_TexelSize.x, _MainTex_TexelSize.y);

        float2 displacement = endPoints.zw - endPoints.xy;

        bool isPermuted = false;

        if (abs(displacement.x) < abs(displacement.y))
        {
            isPermuted = true;

            displacement = displacement.yx;
            endPoints.xyzw = endPoints.yxwz;
        }

        float direction = sign(displacement.x);
        float normalizer = direction / displacement.x;

        segment.direction = (segment.end - segment.start) * normalizer;
        float4 derivatives = float4(float2(direction, displacement.y * normalizer), (homogenizers.y - homogenizers.x) * normalizer, segment.direction.z);

        float stride = 2. - min(1., -segment.start.z * .1);

        derivatives *= stride;
        segment.direction *= stride;

        float2 z = 0.;
        float4 tracker = float4(endPoints.xy, homogenizers.x, segment.start.z);

        UNITY_LOOP
        for(; result.iterationCount < _MaximumIterationCount; ++result.iterationCount)
        {
            tracker += derivatives;

            z.x = z.y;
            z.y = tracker.w + derivatives.w * .5;
            z.y /= tracker.z + derivatives.z * .5;

            if (z.y > z.x)
            {
                float k = z.x;
                z.x = z.y;
                z.y = k;
            }

            result.uv = tracker.xy;

            if (isPermuted)
                result.uv = result.uv.yx;

            result.uv *= _MainTex_TexelSize.xy;

            result.isHit = query(z, result.uv);

            if (result.isHit)
                break;
        }

        segment.start.xy += segment.direction.xy * (float) result.iterationCount;
        segment.start.z = tracker.w;

        result.position = segment.start / tracker.z;

        return result;
    }

    float4 process(in Varyings input) : SV_Target
    {
        Ray ray;

        ray.origin = getViewSpacePosition(input.uv);

        if (ray.origin.z < -_MaximumMarchDistance)
        {
            return tex2D(_MainTex, input.uv);
        }

        float4 gbuffer2 = tex2D(_CameraGBufferTexture2, input.uv);

        float3 normal = 2. * gbuffer2.rgb - 1.;
        normal = normalize(mul((float3x3) _ViewMatrix, normal));

        ray.direction = normalize(reflect(normalize(ray.origin), normal));

        Result result = march(ray);

        if (result.isHit)
        {
            return tex2D(_MainTex, result.uv);
        }

        return tex2D(_MainTex, input.uv);
    }
    ENDCG

    SubShader
    {
        Cull Off ZWrite Off ZTest Off

        Pass
        {
            CGPROGRAM
            #pragma target 3.0
            #pragma vertex vertex
            #pragma fragment process
            ENDCG
        }
    }
}
