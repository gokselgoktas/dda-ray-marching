using UnityEngine;
using System.Collections;

[ExecuteInEditMode]
[RequireComponent(typeof (Camera))]
public class ScreenSpaceRayMarching : MonoBehaviour
{
    [Range(1, 1024)]
    public int maximumIterationCount = 20;

    [Range(0f, 100f)]
    public float maximumMarchDistance = 10f;

    private Shader m_Shader;
    public Shader shader
    {
        get
        {
            if (m_Shader == null)
                m_Shader = Shader.Find("Hidden/Screen-space Ray Marching");

            return m_Shader;
        }
    }

    private Material m_Material;
    public Material material
    {
        get
        {
            if (m_Material == null)
            {
                if (shader == null || !shader.isSupported)
                    return null;

                m_Material = new Material(shader);
            }

            return m_Material;
        }
    }

    private Camera m_Camera;
    public new Camera camera
    {
        get
        {
            if (m_Camera == null)
                m_Camera = GetComponent<Camera>();

            return m_Camera;
        }
    }

    private Camera m_BackFaceCamera;
    private Camera backFaceCamera
    {
        get
        {
            if (m_BackFaceCamera == null)
            {
                GameObject gameObject = new GameObject("Back-face Depth Camera");
                gameObject.hideFlags = HideFlags.HideAndDontSave;

                m_BackFaceCamera = gameObject.AddComponent<Camera>();
            }

            return m_BackFaceCamera;
        }
    }

    private RenderTexture m_BackFaceDepthTexture;

    void OnEnable()
    {
#if !UNITY_5_4_OR_NEWER
        enabled = false;
#endif

        camera.depthTextureMode = DepthTextureMode.Depth;
    }

    void OnDisable()
    {
        if (m_BackFaceCamera)
        {
            DestroyImmediate(m_BackFaceCamera.gameObject);
            m_BackFaceCamera = null;
        }
    }

    void OnPreCull()
    {
        m_BackFaceDepthTexture = RenderTexture.GetTemporary(camera.pixelWidth, camera.pixelHeight, 16, RenderTextureFormat.RHalf);

        backFaceCamera.CopyFrom(camera);
        backFaceCamera.renderingPath = RenderingPath.Forward;
        backFaceCamera.enabled = false;
        backFaceCamera.SetReplacementShader(Shader.Find("Hidden/Back-face Depth Camera"), null);
        backFaceCamera.backgroundColor = new Color(1f, 1f, 1f, 1f);
        backFaceCamera.clearFlags = CameraClearFlags.SolidColor;

        backFaceCamera.targetTexture = m_BackFaceDepthTexture;
        backFaceCamera.Render();
    }

    [ImageEffectOpaque]
    void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if (m_BackFaceDepthTexture)
        {
            material.SetTexture("_CameraBackFaceDepthTexture", m_BackFaceDepthTexture);
        }

        material.SetFloat("_MaximumIterationCount", maximumIterationCount);
        material.SetFloat("_MaximumMarchDistance", maximumMarchDistance);

        Matrix4x4 screenSpaceProjectionMatrix = new Matrix4x4();

        screenSpaceProjectionMatrix.SetRow(0, new Vector4(source.width * 0.5f, 0f, 0f, source.width * 0.5f));
        screenSpaceProjectionMatrix.SetRow(1, new Vector4(0f, source.height * 0.5f, 0f, source.height * 0.5f));
        screenSpaceProjectionMatrix.SetRow(2, new Vector4(0f, 0f, 1f, 0f));
        screenSpaceProjectionMatrix.SetRow(3, new Vector4(0f, 0f, 0f, 1f));

        screenSpaceProjectionMatrix *= camera.projectionMatrix;

        material.SetMatrix("_ViewMatrix", camera.worldToCameraMatrix);
        material.SetMatrix("_InverseViewMatrix", camera.worldToCameraMatrix.inverse);
        material.SetMatrix("_ProjectionMatrix", camera.projectionMatrix);
        material.SetMatrix("_ScreenSpaceProjectionMatrix", screenSpaceProjectionMatrix);

        Graphics.Blit(source, destination, material, 0);
    }

    void OnPostRender()
    {
        RenderTexture.ReleaseTemporary(m_BackFaceDepthTexture);
    }
}
