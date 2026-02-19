export const cropImageToSquareFile = async (file, size = 512) => {
  const objectUrl = URL.createObjectURL(file);

  try {
    const image = await new Promise((resolve, reject) => {
      const element = new Image();
      element.onload = () => resolve(element);
      element.onerror = () => reject(new Error('Failed to load image'));
      element.src = objectUrl;
    });

    const cropSize = Math.min(image.width, image.height);
    const offsetX = Math.max(0, Math.floor((image.width - cropSize) / 2));
    const offsetY = Math.max(0, Math.floor((image.height - cropSize) / 2));

    const canvas = document.createElement('canvas');
    canvas.width = size;
    canvas.height = size;
    const context = canvas.getContext('2d');

    if (!context) {
      throw new Error('Canvas is not available');
    }

    context.drawImage(
      image,
      offsetX,
      offsetY,
      cropSize,
      cropSize,
      0,
      0,
      size,
      size,
    );

    const blob = await new Promise((resolve, reject) => {
      canvas.toBlob(
        (nextBlob) => {
          if (!nextBlob) {
            reject(new Error('Failed to crop image'));
            return;
          }

          resolve(nextBlob);
        },
        'image/webp',
        0.92,
      );
    });

    return new File([blob], `avatar-${Date.now()}.webp`, { type: 'image/webp' });
  } finally {
    URL.revokeObjectURL(objectUrl);
  }
};
